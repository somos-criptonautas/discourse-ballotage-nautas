# discourse-ballotage-nautas

[ENGLISH](README.md) | **ESPAÑOL** | [DEUTSCH](README.de.md)

> Fork de [DaniW42/discourse-ballotage](https://github.com/DaniW42/discourse-ballotage),
> mantenido por [Criptonautas](https://github.com/somos-criptonautas). La documentación
> completa (incluidas las diferencias con el original) está en [inglés](README.md).

Plugin de Discourse para **votaciones secretas** entre miembros: **admisiones** con bolas
negras/blancas y **propuestas** con A favor / En contra / Abstención. Solo se guarda
*que* alguien votó, nunca *qué* votó.

## Qué hace

- **En las publicaciones:** las votaciones se insertan con `[ballotage id=N]` (en el editor,
  ⚙ → «Insertar votación secreta») y se vota directamente en la publicación. El título del
  tema recibe automáticamente la etiqueta **[ADMISIÓN]** o **[PROPUESTA]**, y en las listas
  de temas un icono de urna los distingue.
- **Reglas por votación:** una admisión se rechaza con *N* bolas negras o con *X %* de los
  votos emitidos; las propuestas se aprueban por mayoría simple, de dos tercios o por
  unanimidad (las abstenciones cuentan para el quórum, no para la mayoría). Quórum
  opcional. Las reglas no se pueden cambiar después de crear la votación.
- **Resultado:** al cerrar se fija «Aprobada», «Rechazada» o «Sin quórum» junto con la
  participación. Por votación eliges quién lo ve: solo la supervisión, el resultado, o
  también el recuento — nunca quién votó.
- **Notificaciones** al abrir, 24 h antes del cierre (a quien aún no votó) y al cerrar.
  Crear, cancelar, finalizar y borrar queda registrado en el registro de acciones del staff.
- **Candidato:** una admisión puede indicar el miembro sobre el que se vota (selector
  opcional al crearla; se muestra en la tarjeta).
- **Discourse Workflows:** si está instalado, ofrece el disparador *Votación cambió*
  (creada, abierta, por cerrar, cerrada, cancelada, finalizada; filtros por tipo,
  resultado, categoría y etiquetas) y la acción *Votación secreta* (crear, consultar,
  listar, cancelar, finalizar, listar quién no votó) con los mismos permisos que la web.
  Sin disparador por voto y sin recuento antes de que se publique: el secreto se mantiene.
- **Páginas:** `/ballotage` lista las votaciones programadas y abiertas (arriba a la
  derecha: «Gestionar votaciones» y «Nueva votación» para quien tenga permiso);
  `/ballotage/manage` es la gestión para la supervisión y los administradores. El enlace en
  la barra lateral lo creas tú con la edición normal de la barra lateral de Discourse.

## Secreto del voto

La base de datos no vincula a ningún miembro con su voto: la tabla de participación solo
registra quién votó (sin marcas de tiempo) y los votos son simples contadores. Mientras la
votación está abierta, la supervisión ve la participación pero no el recuento.
Cancelar descarta el recuento en el acto, así que nunca se muestra.
**Finalizar** borra para siempre la lista de quién votó y — salvo que se decida
conservarlo — el recuento; quedan el título, el periodo, el estado y el resultado. Quien
tenga acceso directo a la base de datos podría observar los contadores en vivo; eso debe
controlarse a nivel organizativo.

## Instalación

Añade el plugin con `git clone` en `plugins/` y ejecuta `./launcher rebuild app` (ver la
[guía en inglés](README.md#installation)). Después activa `ballotage_enabled`, elige el
grupo de votación (`ballotage_voting_group`) y el de supervisión
(`ballotage_oversight_group`) y, si quieres, una zona horaria fija (`ballotage_timezone`;
vacía = automática) y la gestión por la supervisión (`ballotage_oversight_can_manage`).

Requisito: Discourse 2026.7 o superior. Código: GPL-3.0 ([LICENSE](LICENSE)).
Este texto: [CC BY-NC-SA 4.0](CC-BY-NC-SA-4.0.txt).
