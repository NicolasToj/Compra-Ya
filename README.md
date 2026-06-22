# 🛒 CompraYa

> **Marketplace de compra y venta en línea, al estilo Mercado Libre.** Una empresa conjunta donde los vendedores son cuentas controladas por la administración, no un mercado abierto a cualquiera.

![Estado](https://img.shields.io/badge/estado-en%20desarrollo-red)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![RLS](https://img.shields.io/badge/seguridad-RLS%20por%20rol-red)
![Responsive](https://img.shields.io/badge/responsive-PC%20%2B%20m%C3%B3vil-red)

El color característico de la marca es el **rojo** 🔴, y está pensada desde el inicio para funcionar igual de bien en **computadora y en celular**.

---

## 🎯 Roles del sistema

| Rol | Qué puede hacer |
|:---|:---|
| 🛍️ **Comprador** | Navega la tienda, busca y filtra productos, guarda favoritos, ve "lo último que viste" y relacionados, arma su carrito, compra y chatea con el vendedor. |
| 🏪 **Vendedor** | Cuentas creadas por el admin. Publican productos (foto, precio, stock, descripción, devolución, entrega), gestionan inventario, responden chats y ven el progreso de sus ventas. |
| 🛡️ **Administrador** | Administración de sistemas. Ve la auditoría de todos los movimientos y las conversaciones archivadas, crea vendedores, gestiona usuarios y modera contenido (deshabilitar cuentas, ocultar mensajes, revisar reportes). |

---

## 🧱 Base de datos

Construida en **PostgreSQL sobre Supabase**, con seguridad a nivel de fila (**RLS**) para que cada rol solo vea y toque lo que le corresponde.

| Tabla | Para qué sirve |
|:---|:---|
| `perfiles` | Datos y rol de cada usuario |
| `categorias` | Categorías de la tienda |
| `productos` | Productos publicados por los vendedores |
| `producto_imagenes` | Galería de fotos de cada producto |
| `favoritos` / `vistos` | Favoritos e historial "lo último que viste" |
| `pedidos` / `pedido_detalle` | Las compras y su detalle |
| `cupones` | Cupones de descuento |
| `conversaciones` / `mensajes` | Chat comprador–vendedor (archivado) |
| `tickets` / `ticket_mensajes` | Soporte hacia el administrador |
| `reportes` | Reportes de contenido para moderación |
| `auditoria` | Registro de cada movimiento (solo lo ve el admin) |

📂 Los scripts SQL están en la carpeta [`base-de-datos/`](./base-de-datos):

- **`compraya_base_de_datos.sql`** — crea toda la estructura inicial.
- **`compraya_base_de_datos_v2.sql`** — agrega soporte, reportes y la capa de control del administrador.

---

## 🛠️ Stack

| Capa | Tecnología |
|:---|:---|
| Base de datos | PostgreSQL (Supabase) |
| Autenticación | Supabase Auth |
| Almacenamiento | Supabase Storage |
| Seguridad | Row Level Security (RLS) por rol |
| Frontend | _en construcción_ 🔜 |

---

## 🚧 Estado del proyecto

| Etapa | Estado |
|:---|:---:|
| Definición del proyecto | ✅ |
| Base de datos | ✅ |
| Backlog (historias de usuario) | ✅ |
| Frontend | 🔜 |
| Conexión front + base | ⬜ |
| Despliegue | ⬜ |

---

## 👤 Autor

Proyecto desarrollado por **Nicolás Torrejón**.

---

<sub>Proyecto en desarrollo. Este repositorio documenta su construcción paso a paso. 🚀</sub>
