Esa es una necesidad muy común y crítica en entornos de clústeres de conmutación por error (Failover Clustering) de Windows, ya que los microcortes de red son la causa más frecuente de failovers innecesarios (llamados "flapping" o "tiempos muertos falsos").

Sí, existe una forma directa de lograr esto, y se gestiona a través de la configuración de Heartbeat (latido) y la sensibilidad de la red dentro del clúster.

Necesitas modificar dos valores clave que controlan la tolerancia del clúster a las fallas transitorias de red:

🛠️ Configuración para Aumentar la Tolerancia a Fallos de Red
Debes modificar las propiedades del clúster relacionadas con la red y el Heartbeat (latido). Esto se hace mejor a través de PowerShell, ya que el Administrador de Failover Cluster no siempre expone estas configuraciones avanzadas.

1. SameSubnetThreshold (Tolerancia a Latidos Perdidos en la Misma Subred)
Esta propiedad define cuántos latidos consecutivos debe perder un nodo antes de que el clúster lo considere desconectado.

Valor Predeterminado (Generalmente): 5

Valor Sugerido para Mayor Tolerancia: 10, 15 o incluso más.

2. SameSubnetDelay (Frecuencia de Latido)
Esta propiedad define cuán a menudo se envían los paquetes de latido (en milisegundos).

Valor Predeterminado (Generalmente): 1000 ms (1 segundo)

📊 Cálculo del Tiempo Total de Espera
El tiempo total que el clúster esperará antes de declarar a un nodo como caído (Down) es el resultado de multiplicar estos dos valores:

Tiempo de Espera Total (ms)=SameSubnetThreshold×SameSubnetDelay
Para lograr el objetivo de 60 segundos (60,000 ms) de tolerancia, puedes establecer los siguientes valores (usando el Delay predeterminado de 1 segundo):

Delay: 1000 ms

Threshold: 60

60×1000 ms=60,000 ms (60 segundos)
💻 Comandos de PowerShell para la Configuración
Debes ejecutar estos comandos en PowerShell como administrador en cualquier nodo del clúster.

PowerShell

# 1. Ajustar el umbral de latidos perdidos a 60 (para un total de 60 segundos de espera)
# La red de "misma subred" (SameSubnet) es generalmente la red privada del clúster (Cluster Heartbeat)

(Get-Cluster).SameSubnetThreshold = 60

# 2. Ajustar el retardo de latido a 1000ms (1 segundo)
(Get-Cluster).SameSubnetDelay = 1000
💡 Caso de Microcortes (500 ms)
Si tu problema son los microcortes de 500 ms y quieres ser aún más tolerante:

Si usas el ajuste de 60 segundos: Un microcorte de 500 ms solo significará que un latido se perdió, pero el clúster esperará 59 latidos más antes de reaccionar.

Ajuste Fino: Si deseas una tolerancia muy fina, puedes aumentar el Threshold a 120 y reducir el Delay a 500 ms (la mitad de un segundo):

120×500 ms=60,000 ms (60 segundos)
PowerShell

# Configuración de extrema tolerancia
(Get-Cluster).SameSubnetThreshold = 120
(Get-Cluster).SameSubnetDelay = 500
⚠️ Advertencia Importante: Redes Cruzadas
Si tus nodos están en diferentes subredes (por ejemplo, clústeres extendidos), también debes modificar las propiedades:

CrossSubnetThreshold

CrossSubnetDelay

Si solo usas una subred, concéntrate únicamente en las propiedades SameSubnet.

Recomendación: Después de realizar este cambio, el clúster esperará los 60 segundos deseados antes de asumir que un nodo ha fallado debido a un problema de red.