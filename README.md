# USAL-SistemasOperativos-II
# Soluciones Prácticas de Sistemas Operativos I (2025-26)

Este repositorio contiene las implementaciones de las dos prácticas evaluables orientadas a la gestión de procesos en C y scripting avanzado en Bash.

---

## P1: El Duelo (Bash)

Scripting de un juego de cartas coleccionables con lógica de inteligencia artificial y persistencia de datos.

### Componentes

* **`duelo.sh`:** Interfaz basada en un menú con opciones de configuración, juego y estadísticas.


* **IA:** Implementación de tres estrategias:
* **0 (Aleatoria):** Sin lógica de selección.


* **1 (Ofensiva):** Foco en daño al oponente con más puntos de vida.


* **2 (Defensiva):** Prioridad en escudos y curación.




* **Sistema de Log:** Registro en formato CSV para el cálculo de medias de tiempo, porcentajes de victoria y detección de empates.



### Mecánicas

* **Configuración:** Fichero `config.cfg` editable interactivamente sin usar editores de texto externos.


* **Cartas:** Tipos de ataque (espadas, hacha), defensa (escudos) y magia (curación, robo, contraataque).


---

## P2: Los Ángeles de Charlie (C)

Simulación de concurrencia, señales e IPC mediante una jerarquía de procesos inspirada en la serie homónima.

### Arquitectura de Procesos

* **Charlie (Padre):** Nodo raíz que coordina la creación de Bosley y del Malo.


* **Bosley (Hijo de Charlie):** Actúa como enlace de comunicación y gestor de los ángeles.


* **Los Ángeles (Hijas de Bosley):** Sabrina, Jill y Kelly disparan señales `SIGTERM` al Malo. Si el PID objetivo es correcto, eliminan la reencarnación.


* **El Malo (Hijo de Charlie):** Una saga de 20 reencarnaciones sucesivas; cada proceso genera un hijo antes de morir. El último proceso es un "malo culto" que domina el latín.



### Detalles Técnicos

* **Memoria Proyectada:** Uso de `mmap` sobre un fichero binario para compartir una tabla de 20 PIDs (80 bytes).


* **Sincronización:** Evita la espera ocupada mediante el uso adecuado de señales y pausas selectivas.


* **Modo Veloz:** Argumento opcional `-v` que omite los retardos aleatorios (`sleep`).


* **Aleatoriedad:** Semillas basadas en `time` y `getpid` para garantizar disparos y reencarnaciones no deterministas.



---

## Restricciones de Implementación

* **Llamadas al Sistema:** Uso preferente sobre funciones de biblioteca; prohibido el uso de `system()`.


* **Salida de Datos:** Uso de `write` para evitar interferencias de buffers en la concurrencia.


* **Gestión de Errores:** Limpieza automática de procesos huérfanos y ficheros temporales al recibir `CTRL-C`.
