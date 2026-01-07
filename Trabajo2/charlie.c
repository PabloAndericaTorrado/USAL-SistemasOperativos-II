#define _XOPEN_SOURCE 500
#define __EXTENSIONS__        
#define _POSIX_C_SOURCE 199506L

#include <stdio.h>      
#include <unistd.h>     
#include <fcntl.h>
#include <signal.h>     
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdarg.h>     
#include <string.h>     
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif



#define NUM_SLOTS_PIDS 20
#define TAM_BUF_MSJ    512
#define FICHERO_PIDS   "pids.bin"


#define RES_SABRINA 1
#define RES_JILL    2
#define RES_KELLY   4


static const char *ruta_ejecutable_programa = NULL;



static sigset_t mascara_senales_bloqueo;

static void bloquear_senales_de_arranque(void)
{
    sigemptyset(&mascara_senales_bloqueo);
    sigaddset(&mascara_senales_bloqueo, SIGUSR1);
    sigaddset(&mascara_senales_bloqueo, SIGUSR2);

    if (sigprocmask(SIG_BLOCK, &mascara_senales_bloqueo, NULL) < 0) {
        perror("sigprocmask");
        _exit(1);
    }
}



static volatile sig_atomic_t hay_sigint_pendiente = 0;

static pid_t pid_bosley_raiz = -1;
static pid_t pid_malo_raiz   = -1;

static void terminar_ejecucion_por_sigint(void);
static void matar_todos_los_malos_registrados(void);



static void imprimir_mensaje(const char *fmt, ...)
{
    char    buf[TAM_BUF_MSJ];
    va_list ap;
    int     n;

    va_start(ap, fmt);
    n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (n <= 0)
        return;
    if (n > (int)sizeof(buf))
        n = (int)sizeof(buf);

    ssize_t escritos = 0;
    while (escritos < n) {
        ssize_t r = write(STDOUT_FILENO, buf + escritos, (size_t)(n - escritos));
        if (r < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (r == 0)
            break;
        escritos += r;
    }
}



static void manejador_usr_despertar(int sig)
{
    (void)sig; 
}

static void instalar_manejadores_usr(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = manejador_usr_despertar;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    sigaction(SIGUSR1, &sa, NULL);
    sigaction(SIGUSR2, &sa, NULL);
}



static void manejador_sigterm_malo(int sig)
{
    (void)sig;
    imprimir_mensaje("MALO: AY, me han dado... pulvis sumus, collige, virgo, rosas\n");
    _exit(0);
}



static void manejador_sigint_charlie(int sig)
{
    (void)sig;
    hay_sigint_pendiente = 1;
}



static void inicializar_generador_azar(void)
{
    unsigned int semilla =
        (unsigned int)(time(NULL) ^ ((unsigned long)getpid() << 16));
    srand(semilla);
}


static int obtener_azar_en_rango(int a, int b)
{
    if (a >= b)
        return a;
    return a + (int)(rand() / (1.0 + RAND_MAX) * (b - a + 1));
}



typedef enum {
    VEL_NORMAL = 0,
    VEL_VELOZ  = 1
} t_velocidad;

static t_velocidad modo_velocidad = VEL_NORMAL;

static void mostrar_ayuda_y_salir(const char *progname)
{
    imprimir_mensaje("Uso: %s [normal|veloz]\n", progname);
    _exit(1);
}

static void configurar_modo_velocidad(int argc, char *argv[])
{
    if (argc == 1) {
        modo_velocidad = VEL_NORMAL;
        return;
    }

    if (argc == 2) {
        if (strcmp(argv[1], "normal") == 0) {
            modo_velocidad = VEL_NORMAL;
        } else if (strcmp(argv[1], "veloz") == 0) {
            modo_velocidad = VEL_VELOZ;
        } else {
            mostrar_ayuda_y_salir(argv[0]);
        }
        return;
    }

    mostrar_ayuda_y_salir(argv[0]);
}


static void dormir_intervalo(int min_s, int max_s)
{
    if (modo_velocidad == VEL_VELOZ)
        return;

    int t = obtener_azar_en_rango(min_s, max_s);
    while (t > 0) {
        unsigned int r = sleep((unsigned int)t);
        if (r == 0)
            break;
        t = (int)r;
    }
}




static void crear_fichero_tabla_pids(void)
{
    int fd_pids;
    size_t tam_tabla_pids = NUM_SLOTS_PIDS * sizeof(int32_t);
    int32_t tabla_pids_inicial[NUM_SLOTS_PIDS];

    memset(tabla_pids_inicial, 0, sizeof(tabla_pids_inicial));

    fd_pids = open(FICHERO_PIDS, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd_pids < 0) {
        perror("CHARLIE: open pids.bin");
        _exit(1);
    }

    ssize_t bytes_escritos = 0;
    const char *puntero_buffer = (const char *)tabla_pids_inicial;
    while ((size_t)bytes_escritos < tam_tabla_pids) {
        ssize_t r = write(fd_pids,
                          puntero_buffer + bytes_escritos,
                          tam_tabla_pids - (size_t)bytes_escritos);
        if (r < 0) {
            if (errno == EINTR)
                continue;
            perror("CHARLIE: write inicializando pids.bin");
            close(fd_pids);
            _exit(1);
        }
        if (r == 0)
            break;
        bytes_escritos += r;
    }

    if ((size_t)bytes_escritos < tam_tabla_pids) {
        imprimir_mensaje("CHARLIE: Error, no se han podido escribir todos los bytes en %s\n",
                         FICHERO_PIDS);
        close(fd_pids);
        _exit(1);
    }

    close(fd_pids);
}



static void matar_todos_los_malos_registrados(void)
{
    int fd_pids = open(FICHERO_PIDS, O_RDONLY);
    if (fd_pids < 0) {
        return;
    }

    size_t tam_tabla_pids = NUM_SLOTS_PIDS * sizeof(int32_t);
    int32_t *tabla_pids_mapeada =
        (int32_t *)mmap(NULL, tam_tabla_pids, PROT_READ, MAP_SHARED, fd_pids, 0);
    if (tabla_pids_mapeada == MAP_FAILED) {
        perror("mmap pids.bin en matar_todos_los_malos");
        close(fd_pids);
        return;
    }
    close(fd_pids);

    int indice;
    for (indice = 0; indice < NUM_SLOTS_PIDS; ++indice) {
        if (tabla_pids_mapeada[indice] != 0) {
            
            kill((pid_t)tabla_pids_mapeada[indice], SIGKILL);
        }
    }

    munmap(tabla_pids_mapeada, tam_tabla_pids);
}



static int ejecutar_charlie(int argc, char *argv[]);
static int ejecutar_bosley(int argc, char *argv[]);
static int ejecutar_angel(const char *nombre, int argc, char *argv[]);
static int ejecutar_malo(int argc, char *argv[]);




static void esperar_senal_sincronizacion(int signo)
{
    sigset_t mascara_espera = mascara_senales_bloqueo;
    sigdelset(&mascara_espera, signo);
    (void)sigsuspend(&mascara_espera);
}


static void esperar_senal_charlie_o_ctrlc(int signo)
{
    for (;;) {
        if (hay_sigint_pendiente)
            terminar_ejecucion_por_sigint();

        sigset_t mascara_espera = mascara_senales_bloqueo;
        sigdelset(&mascara_espera, signo);
        (void)sigsuspend(&mascara_espera);

        if (hay_sigint_pendiente)
            terminar_ejecucion_por_sigint();

        break;
    }
}



static void terminar_ejecucion_por_sigint(void)
{
    int estado_hijo;

    
    struct sigaction accion_ignorar_sigterm;
    memset(&accion_ignorar_sigterm, 0, sizeof(accion_ignorar_sigterm));
    accion_ignorar_sigterm.sa_handler = SIG_IGN;
    sigemptyset(&accion_ignorar_sigterm.sa_mask);
    accion_ignorar_sigterm.sa_flags = 0;
    if (sigaction(SIGTERM, &accion_ignorar_sigterm, NULL) < 0) {
        perror("CHARLIE: sigaction SIGTERM");
        _exit(1);
    }

    
    if (kill(0, SIGTERM) < 0) {
        perror("CHARLIE: kill(0, SIGTERM)");
    }

    
    matar_todos_los_malos_registrados();

    
    while (waitpid(-1, &estado_hijo, 0) > 0)
        ;

    imprimir_mensaje("Programa interrumpido\n");
    _exit(1);
}



static int ejecutar_charlie(int argc, char *argv[])
{
    pid_t pid_bosley;
    pid_t pid_malo;
    int   status_malo;
    int   status_bosley;

    configurar_modo_velocidad(argc, argv);

    
    struct sigaction accion_sigint;
    memset(&accion_sigint, 0, sizeof(accion_sigint));
    accion_sigint.sa_handler = manejador_sigint_charlie;
    sigemptyset(&accion_sigint.sa_mask);
    accion_sigint.sa_flags = 0;
    sigaction(SIGINT, &accion_sigint, NULL);

    

    pid_bosley = fork();
    if (pid_bosley < 0) {
        perror("CHARLIE: fork Bosley");
        _exit(1);
    }

    if (pid_bosley == 0) {
        char *args_b[3];

        args_b[0] = (char *)"bosley";
        args_b[1] = (modo_velocidad == VEL_VELOZ) ? (char *)"veloz" : (char *)"normal";
        args_b[2] = NULL;

        if (ruta_ejecutable_programa == NULL) {
            _exit(1);
        }

        execv(ruta_ejecutable_programa, args_b);
        perror("execv bosley");
        _exit(1);
    }

    pid_bosley_raiz = pid_bosley;

    imprimir_mensaje("CHARLIE: Bosley, hijo de mis entretelas, tu PID es %ld. Espero a que me avises...\n",
                     (long)pid_bosley);

    
    esperar_senal_charlie_o_ctrlc(SIGUSR1);

    imprimir_mensaje("CHARLIE: Veo que los Angeles ya han nacido. Creo al malo...\n");

    
    crear_fichero_tabla_pids();

    

    pid_malo = fork();
    if (pid_malo < 0) {
        perror("CHARLIE: fork Malo");
        _exit(1);
    }

    if (pid_malo == 0) {
        char *args_m[3];

        args_m[0] = (char *)"malo";
        args_m[1] = (modo_velocidad == VEL_VELOZ) ? (char *)"veloz" : (char *)"normal";
        args_m[2] = NULL;

        if (ruta_ejecutable_programa == NULL) {
            _exit(1);
        }

        execv(ruta_ejecutable_programa, args_m);
        perror("execv malo");
        _exit(1);
    }

    pid_malo_raiz = pid_malo;

    imprimir_mensaje("CHARLIE: El malo ha nacido y su PID es %ld. Aviso a Bosley\n",
                     (long)pid_malo);

    
    if (kill(pid_bosley, SIGUSR2) < 0) {
        perror("CHARLIE: kill(SIGUSR2 a Bosley)");
    }

    
    for (;;) {
        if (hay_sigint_pendiente) {
            terminar_ejecucion_por_sigint();
        }

        pid_t pid_terminado = waitpid(pid_malo, &status_malo, 0);
        if (pid_terminado < 0) {
            if (errno == EINTR) {
                if (hay_sigint_pendiente) {
                    terminar_ejecucion_por_sigint();
                }
                continue;
            }
            perror("CHARLIE: waitpid(malo)");
            _exit(1);
        }
        break;
    }

    
    for (;;) {
        if (hay_sigint_pendiente) {
            terminar_ejecucion_por_sigint();
        }

        pid_t pid_terminado = waitpid(pid_bosley, &status_bosley, 0);
        if (pid_terminado < 0) {
            if (errno == EINTR) {
                if (hay_sigint_pendiente) {
                    terminar_ejecucion_por_sigint();
                }
                continue;
            }
            perror("CHARLIE: waitpid(bosley)");
            _exit(1);
        }
        break;
    }

    int mascara_resultado = 0;
    if (WIFEXITED(status_bosley)) {
        mascara_resultado = WEXITSTATUS(status_bosley) & 0x7;  
    }

 

    switch (mascara_resultado) {
    case 0: 
        imprimir_mensaje("CHARLIE: El pAjaro volO. Ahora se pone tibio a daiquiris en el Caribe\n");
        break;

    case RES_SABRINA: 
        imprimir_mensaje("CHARLIE: Bien hecho, Sabrina, siempre fuiste mi favorita\n");
        break;

    case RES_JILL:    
        imprimir_mensaje("CHARLIE: Jill, donde pones el ojo, pones la bala\n");
        break;

    case RES_KELLY:  
        imprimir_mensaje("CHARLIE: Bravo por Kelly\n");
        break;

    case RES_SABRINA | RES_JILL:  
        imprimir_mensaje("CHARLIE: Kelly, mala suerte, tus compaNeras acertaron y tU, no\n");
        break;


    case RES_JILL | RES_KELLY:    
        imprimir_mensaje("CHARLIE: Sabrina, otra vez serA, te apuntarE a una academia de tiro\n");
        break;

    case RES_SABRINA | RES_KELLY: 
        imprimir_mensaje("CHARLIE: Jill, no te preocupes, las pistolas no suelen ");
        imprimir_mensaje("funcionar cuando mAs lo necesitas\n");
        break;

    case RES_SABRINA | RES_JILL | RES_KELLY: 
        imprimir_mensaje("CHARLIE: Pobre malo. Le habEis dejado como un colador... Sois unos Angeles letales\n");
        break;
    }

   
    matar_todos_los_malos_registrados();

    return 0;
}



static int ejecutar_bosley(int argc, char *argv[])
{
    static const char *nombres_angeles[3] = { "sabrina", "jill", "kelly" };
    pid_t pids_angeles[3];
    int i;

    configurar_modo_velocidad(argc, argv);

    imprimir_mensaje("BOSLEY: Hola, papA, dOnde estA mamA? Mi PID es %ld y voy a crear a los Angeles...\n",
                     (long)getpid());

    
    for (i = 0; i < 3; i++) {
        pid_t pid = fork();
        if (pid < 0) {
            perror("BOSLEY: fork angel");
            _exit(1);
        }

        if (pid == 0) {
            char *args_a[3];

            args_a[0] = (char *)nombres_angeles[i];
            args_a[1] = (modo_velocidad == VEL_VELOZ) ? (char *)"veloz" : (char *)"normal";
            args_a[2] = NULL;

            if (ruta_ejecutable_programa == NULL) {
                _exit(1);
            }

            execv(ruta_ejecutable_programa, args_a);
            perror("execv angel");
            _exit(1);
        } else {
            pids_angeles[i] = pid;
        }
    }

  
    kill(getppid(), SIGUSR1);

    
    esperar_senal_sincronizacion(SIGUSR2);

    
    for (i = 0; i < 3; i++) {
        if (kill(pids_angeles[i], SIGUSR2) < 0) {
            perror("BOSLEY: kill(SIGUSR2 a angel)");
        }
    }

    
    int vivos = 3;
    int resultado = 0;

    while (vivos > 0) {
        int status;
        pid_t pid = wait(&status);
        if (pid < 0) {
            if (errno == EINTR)
                continue;
            perror("BOSLEY: wait");
            break;
        }

        int exito = 0;
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            exito = 1;
        }

        if (pid == pids_angeles[0]) {
            if (exito) resultado |= RES_SABRINA;
        } else if (pid == pids_angeles[1]) {
            if (exito) resultado |= RES_JILL;
        } else if (pid == pids_angeles[2]) {
            if (exito) resultado |= RES_KELLY;
        }

        vivos--;
    }

    imprimir_mensaje("BOSLEY: Los tres Angeles han acabado su misiOn. Informo del resultado a Charlie y muero\n");

    _exit(resultado & 0xFF);
}



static int ejecutar_malo(int argc, char *argv[])
{
    int fd;
    size_t tam = NUM_SLOTS_PIDS * sizeof(int32_t);
    int32_t *tabla_pids;

    configurar_modo_velocidad(argc, argv);

    fd = open(FICHERO_PIDS, O_RDWR);
    if (fd < 0) {
        perror("MALO: open pids.bin");
        _exit(1);
    }

    tabla_pids = (int32_t *)mmap(NULL, tam,
                                 PROT_READ | PROT_WRITE,
                                 MAP_SHARED, fd, 0);
    if (tabla_pids == MAP_FAILED) {
        perror("MALO: mmap pids.bin");
        close(fd);
        _exit(1);
    }
    close(fd);

    inicializar_generador_azar();
    int generacion;
    
    for (generacion = 1; generacion <= 20; generacion++) {

        pid_t pid_hijo = fork();
        if (pid_hijo < 0) {
            perror("MALO: fork");
            munmap(tabla_pids, tam);
            _exit(1);
        }

        if (pid_hijo == 0) {
            

            
            struct sigaction sa;
            memset(&sa, 0, sizeof(sa));
            sa.sa_handler = manejador_sigterm_malo;
            sigemptyset(&sa.sa_mask);
            sa.sa_flags = 0;
            if (sigaction(SIGTERM, &sa, NULL) < 0) {
                perror("MALO: sigaction SIGTERM en hijo");
                _exit(1);
            }

            imprimir_mensaje("MALO: JA, JA, JA, me acabo de reencarnar y mi nuevo PID es: ");
            imprimir_mensaje("%ld. QuE malo que soy...\n",
                             (long)getpid());

          
            if (generacion >= 1 && generacion <= NUM_SLOTS_PIDS) {
                int libre = -1;
                int intentos;
                
                for (intentos = 0; intentos < 40; ++intentos) {
                    int idx = obtener_azar_en_rango(0, NUM_SLOTS_PIDS - 1);
                    if (tabla_pids[idx] == 0) {
                        libre = idx;
                        break;
                    }
                }
                int idx;
                
                if (libre < 0) {
                    for (idx = 0; idx < NUM_SLOTS_PIDS; ++idx) {
                        if (tabla_pids[idx] == 0) {
                            libre = idx;
                            break;
                        }
                    }
                }
                if (libre >= 0) {
                    tabla_pids[libre] = (int32_t)getpid();
                }
            }

            
            dormir_intervalo(1, 3);

            _exit(0);
        } else {
            
            int status;
            for (;;) {
                pid_t r = waitpid(pid_hijo, &status, 0);
                if (r < 0) {
                    if (errno == EINTR)
                        continue;
                    perror("MALO: waitpid(generacion)");
                    munmap(tabla_pids, tam);
                    _exit(1);
                }
                break;
            }
        }
    }

 
    imprimir_mensaje("MALO: He sobrevivido a mi vigEsima reencarnaciOn. Hago mutis por el foro\n");
    munmap(tabla_pids, tam);
    _exit(0);
}




static int ejecutar_angel(const char *nombre, int argc, char *argv[])
{
    int fd;
    size_t tam = NUM_SLOTS_PIDS * sizeof(int32_t);
    const int32_t *tabla_pids;
    int disparo;
    int exito_alguna_vez = 0;  

    configurar_modo_velocidad(argc, argv);
    inicializar_generador_azar();

    imprimir_mensaje("%s: Hola, he nacido y mi PID es %ld\n",
                     nombre, (long)getpid());

    
    esperar_senal_sincronizacion(SIGUSR2);

    
    fd = open(FICHERO_PIDS, O_RDONLY);
    if (fd < 0) {
        perror("ANGEL: open pids.bin");
        _exit(1);
    }

    tabla_pids = (const int32_t *)mmap(NULL, tam,
                                       PROT_READ,
                                       MAP_SHARED, fd, 0);
    if (tabla_pids == MAP_FAILED) {
        perror("ANGEL: mmap pids.bin");
        close(fd);
        _exit(1);
    }
    close(fd);

    for (disparo = 1; disparo <= 3; disparo++) {

        
        dormir_intervalo(6, 12);

        int idx    = obtener_azar_en_rango(0, NUM_SLOTS_PIDS - 1);
        int32_t valor = tabla_pids[idx];

        if (valor == 0) {
            imprimir_mensaje("%s: Pardiez! La pistola se ha encasquillado\n", nombre);
            continue;
        }

        pid_t objetivo = (pid_t)valor;

        imprimir_mensaje("%s: Voy a disparar al PID %ld\n",
                         nombre, (long)objetivo);

        if (kill(objetivo, SIGTERM) == 0) {
            
            imprimir_mensaje("%s: BINGO! He hecho diana! Un malo menos\n", nombre);
            exito_alguna_vez = 1;
            
        } else {
            if (errno == ESRCH) {
                
                imprimir_mensaje("%s: He fallado. Vuelvo a intentarlo\n", nombre);
            } else {
                
                perror("ANGEL: kill(SIGTERM al malo)");
                imprimir_mensaje("%s: He fallado ya tres veces y no me quedan mAs balas. Muero\n", nombre);
                munmap((void *)tabla_pids, tam);
                _exit(1);
            }
        }
    }

    
    if (exito_alguna_vez) {
        
        munmap((void *)tabla_pids, tam);
        _exit(0);
    } else {
        imprimir_mensaje("%s: He fallado ya tres veces y no me quedan mAs balas. Muero\n", nombre);
        munmap((void *)tabla_pids, tam);
        _exit(1);
    }
}




int main(int argc, char *argv[])
{
    bloquear_senales_de_arranque();
    instalar_manejadores_usr();

    const char *ruta_env_ejecutable = getenv("CHARLIE_PATH");
    if (ruta_env_ejecutable != NULL && ruta_env_ejecutable[0] != '\0') {
        ruta_ejecutable_programa = ruta_env_ejecutable;
    } else {
        ruta_ejecutable_programa = argv[0];
        (void)setenv("CHARLIE_PATH", ruta_ejecutable_programa, 1);
    }

    const char *nombre_programa = argv[0];
    const char *ultima_barra = strrchr(nombre_programa, '/');
    if (ultima_barra != NULL)
        nombre_programa = ultima_barra + 1;

    if (strcmp(nombre_programa, "charlie") == 0) {
        return ejecutar_charlie(argc, argv);
    } else if (strcmp(nombre_programa, "bosley") == 0) {
        return ejecutar_bosley(argc, argv);
    } else if (strcmp(nombre_programa, "sabrina") == 0) {
        return ejecutar_angel("SABRINA", argc, argv);
    } else if (strcmp(nombre_programa, "jill") == 0) {
        return ejecutar_angel("JILL", argc, argv);
    } else if (strcmp(nombre_programa, "kelly") == 0) {
        return ejecutar_angel("KELLY", argc, argv);
    } else if (strcmp(nombre_programa, "malo") == 0) {
        return ejecutar_malo(argc, argv);
    }

    return ejecutar_charlie(argc, argv);
}
