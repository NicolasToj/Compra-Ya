🛒 CompraYa
CompraYa es una plataforma de e-commerce para compra y venta en línea, al estilo Mercado Libre, pensada como una empresa conjunta donde los vendedores son cuentas controladas por la administración (no un marketplace abierto a cualquiera).
El color característico de la marca es el rojo, y está pensada desde el inicio para funcionar igual en PC y en móvil.
---
🎯 ¿Qué hace?
La plataforma maneja tres tipos de usuario, cada uno con su propio espacio:
Comprador — navega la tienda, busca productos, filtra por categoría, guarda favoritos, ve "lo último que viste" y productos relacionados, arma su carrito, compra y puede hablar con el vendedor por chat.
Vendedor — cuentas creadas por el administrador. Publican productos (con foto, precio, stock, descripción, devolución y fecha de entrega), gestionan su inventario, responden chats y ven el progreso de sus ventas.
Administrador — administración de sistemas. Ve el registro de auditoría de todos los movimientos, todas las conversaciones archivadas, gestiona usuarios y roles, crea vendedores, y modera contenido (deshabilitar cuentas, ocultar mensajes, revisar reportes).
---
🧱 Base de datos
La base está construida en PostgreSQL sobre Supabase, con seguridad a nivel de fila (RLS) para que cada rol solo vea y toque lo que le corresponde.
Tablas principales:
Tabla	Para qué sirve
`perfiles`	Datos y rol de cada usuario (comprador / vendedor / admin)
`categorias`	Categorías de la tienda
`productos`	Productos publicados por los vendedores
`producto_imagenes`	Galería de fotos de cada producto
`favoritos` / `vistos`	Favoritos y el historial "lo último que viste"
`pedidos` / `pedido_detalle`	Las compras y su detalle
`cupones`	Cupones de descuento
`conversaciones` / `mensajes`	Chat entre comprador y vendedor (archivado)
`tickets` / `ticket_mensajes`	Soporte hacia el administrador
`reportes`	Reportes de contenido para moderación
`auditoria`	Registro de cada movimiento importante (solo lo ve el admin)
Los scripts SQL están en la carpeta `base-de-datos/`:
`compraya_base_de_datos.sql` — crea toda la estructura inicial.
`compraya_base_de_datos_v2.sql` — agrega soporte, reportes y la capa de control del administrador.
---
🛠️ Stack
Base de datos / Backend: Supabase (PostgreSQL, Auth, Storage)
Seguridad: Row Level Security (RLS) por rol
Frontend: (en construcción)
---
🚧 Estado del proyecto
Etapa	Estado
Definición del proyecto	✅
Base de datos	✅
Backlog (historias de usuario)	✅
Frontend	🔜 En construcción
Conexión front + base	⬜
Despliegue	⬜
---
👤 Autor
Proyecto desarrollado por Nicolás Torrejón.
---
> Proyecto en desarrollo. Este repositorio documenta su construcción paso a paso.
