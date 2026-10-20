# Preguntas del revisor: observaciones que decidimos NO cambiar

Revisión final de calidad del 05/10/2026. Estas son las cosas que un revisor podría marcar en el Code Review y que **dejamos a propósito**. Para cada una: qué te pueden preguntar, qué responder y qué pasaría si lo cambiáramos.

Las observaciones que sí se corrigieron (help text en inglés, `ErrorLogUtil.saveLogsForFailedResults`, factory en el test bulk, asserts de los Schedulers, ApexDoc de los constructores, scripts de la plantilla) están en el commit de la revisión y en DEV2.md.

---

## 1. "¿Por qué estas constantes son `public` si nadie las usa afuera? ¿Y por qué en los tests a veces escribís `'Draft'` y a veces usás la constante?"

**Dónde:** `QuoteTriggerHandler.STATUS_APPROVED`, `QuoteExpirationBatch.STATUS_IN_REVIEW` y `RECALL_ACTION`, `RenewalQuoteBatch.DAYS_BEFORE_END`, `QuoteProgressController.APPROVED_STATUS_SET`. En los tests: `OrderTriggerHandlerTest`, `QuoteTriggerHandlerTest`, `QuoteExpirationBatchTest` y `QuoteProgressControllerTest` usan `'Draft'`, `'Approved'`, `'In Review'` o `'Activated'` escritos sueltos.

**Respuesta:**
- Son `public` porque son el valor que define la regla de cada clase, y otra clase lo puede necesitar. Ya pasó: `STATUS_ACTIVATED` del `ContractTriggerHandler` la terminó usando `RenewalQuoteBatch`, y `READY_PRICE_CALC_STATUSES` la usa el Queueable del DEV #2. Que sean `public` no las deja cambiar: son `static final`.
- En los tests, el valor escrito a mano es a propósito. Un test que compara con la constante compara la constante consigo misma: si alguien la cambia por error (por ejemplo, `'Aproved'`), el test **igual pasa**. Con `'Approved'` escrito en el test, ese error se detecta, porque el test conoce el valor real del picklist.
- Donde el test usa la constante (`ContractTriggerHandlerTest`, `RenewalQuoteBatchTest`) es solo para **armar el dato** (activar el Contract), no para verificar el resultado.

**Si lo cambiáramos:** con `private` en las que no se usan afuera no se rompe nada, pero la próxima clase que las necesite va a terminar copiándolas, que es justo la duplicación que sacamos en el DEV #3.

---

## 2. "`return true; else return false;` es redundante, ¿por qué no `return condición;`?"

**Dónde:** `OrderTriggerHandler.isReadyToActivate`, `SubscriptionTriggerHandler.hasRelevantChange`, `ActiveSubscriptionCounter.isInForceToday`.

**Respuesta:**
- Es el estilo del training (Módulo 1): todo condicional con su `if`, sus llaves y nada de atajos "ingeniosos" en una sola línea.
- Se lee igual de rápido que `return condición;`, y en `isInForceToday` las 3 condiciones tienen nombre propio (`hasStarted`, `hasNotEnded`, `isNotTerminated`), así que el `if` dice en palabras qué significa "activa".
- Hace exactamente lo mismo: el compilador no genera nada distinto que importe.

**Si lo cambiáramos:** son 3 líneas menos por método, pero se mezclarían dos estilos en el mismo proyecto.

---

## 3. "Los helpers `getAccountId()`, `getProductId()`, `getActiveCount()` están repetidos en varios tests. ¿No es DRY?"

**Dónde:** `getAccountId` en 8 test classes, `getProductId` en 4, `getActiveCount` en 3.

**Respuesta:**
- Son de **una línea**: una query que lee lo que creó el `@testSetup` de **esa** clase. Cada test class se puede leer sola, de arriba a abajo, sin saltar a otro archivo.
- La lógica que sí se repetiría (crear los registros) está en `TestDataFactory`. Eso es el DRY que importa: si cambia cómo se arma un Contract o una Order, se cambia en un solo lugar.
- Además, cada helper depende de cómo armó los datos su clase (por ejemplo, `getContractId()` busca el Contract de 12 meses porque ese test arma uno de 12 y otro de 24). Moverlos a la factory haría que la factory "sepa" de los datos de cada test.

**Si lo cambiáramos:** `TestDataFactory.getAccountId()` funcionaría, pero ganaríamos una línea por clase a cambio de un acoplamiento entre la factory y cada test.

---

## 4. "`CLASS_NAME = 'OrderTriggerHandler'` está escrito a mano. Si renombrás la clase, el log queda mal."

**Dónde:** 6 clases (`OrderTriggerHandler`, `OrderActivationQueueable`, `QuoteTriggerHandler`, `QuoteExpirationBatch`, `ActiveSubscriptionCounter`, `RenewalQuoteBatch`).

**Respuesta:**
- Es cierto. La alternativa es `OrderTriggerHandler.class.getName()`, que devuelve el nombre sola.
- Lo dejamos como texto porque es lo más simple y se ve en el primer vistazo qué va a aparecer en el campo `Class_Name__c`. Renombrar una clase en Salesforce es raro (hay que borrar y crear, y actualizar todas las referencias), y en ese caso la constante está en la misma clase, dos líneas abajo del nombre.
- Los tests del DEV #2 (`logErrorWhenQueueableLimitReachedTest`, `logErrorWhenActivationFailsTest`) verifican el `Class_Name__c` con el nombre escrito a mano, así que en esas clases un nombre mal copiado se detectaría.

**Si lo cambiáramos:** no cambia el comportamiento; agrega algo que no vimos en el training para cubrir un caso (renombrar) que casi no pasa.

---

## 5. "Hay inconsistencias chicas: `READY_PRICE_CALC_STATUSES` vs `APPROVED_STATUS_SET`, `TODAY` vs `:today`, y la variable `con` se puede confundir con Contact."

**Respuesta:**
- **Nombres de los Set:** los dos son claros y dicen qué contienen. Renombrar uno ahora es cambiar nombres en código ya probado, deployado y documentado, solo por estética.
- **`TODAY` vs `:today`:** los dos son correctos. En `QuoteExpirationBatch` alcanza con la palabra de SOQL `TODAY`. En `RenewalQuoteBatch` la ventana es de hoy a hoy + 30. SOQL tiene `NEXT_N_DAYS:30`, pero **empieza mañana** (no incluye hoy) y escondería el número 30 adentro de la query. Con las variables `today` y `windowEndDate` el rango se ve exacto y usa la constante `DAYS_BEFORE_END`; ya que hay variable para el fin, se usa la misma para el inicio.
- **`con`:** en todo el proyecto `con` es siempre un `Contract` (no hay ningún Contact), y el tipo está escrito al lado (`Contract con`), así que no hay ambigüedad al leerlo.

**Si lo cambiáramos:** son cambios de nombre en varias clases, con su deploy (pausando los jobs) y su re-corrida de tests, sin cambiar nada de lo que hace el código.

---

## 6. "Usás cosas que no están en el training: `SYSTEM_MODE`, `Database.update( lista, false )`, `SBQQ.TriggerControl`, `catch ( Exception e )`, una clase interna..."

**Respuesta (una por una):**
- **`AccessLevel.SYSTEM_MODE` / `WITH SYSTEM_MODE`:** el Error Log es un registro del sistema. Si el usuario que disparó el proceso no tiene permiso sobre `Error_Log__c`, el insert del log fallaría y **cancelaría el proceso que queríamos proteger**. Quién puede *ver* los logs lo sigue controlando el permission set `Error_Log_Access`. En los tests, `WITH SYSTEM_MODE` hace que el assert no dependa de los permisos del usuario que corre el test.
- **`Database.update( lista, false )`:** es el `update` del training con un parámetro: "si un registro falla, guardá igual los demás". Sin eso, un solo Contract con un problema cancelaría el recuento de los otros 199, o el contracting de CPQ. Los fallidos no se pierden: van a `Error_Log__c`.
- **`SBQQ.TriggerControl.disable()`:** es la API del paquete CPQ para apagar **sus** triggers. Se usa en 3 tests y solo para armar datos o medir **nuestra** bulkificación: con 200 Contracts, el código de CPQ (no el nuestro) rompe el límite de 100 queries. Los demás tests corren con CPQ prendido.
- **`catch ( Exception e )` genérico:** está solo en el envío del email (DEV #3). Ese código corre **dentro** del save en el que CPQ crea la Quote: cualquier excepción sin atrapar haría rollback de la Renewal Quote. No importa qué tipo de error sea (Deliverability apagado, Owner inactivo): lo que queremos es que la Quote se guarde igual y que el error quede en el Error Log, sin fallar en silencio (Módulo 3).
- **Clase interna `ProgressStep`:** es la forma de mandarle al LWC una lista de pasos con 2 datos cada uno (texto y si está hecho). Tiene 2 campos y un constructor; no es una "clase wrapper compleja". La alternativa (un `Map<String, Boolean>`) no garantiza el orden de los pasos.
- **`List<SObject>` como parámetro:** `SObject` es el tipo base de cualquier registro. Permite que `ErrorLogUtil.saveLogsForFailedResults` sirva para Orders, Contracts y Opportunities. No son "genéricos" (no hay `<T>`).

**Si lo cambiáramos:** cada una de estas cosas resuelve un problema real que encontramos en el org (está documentado en el DEVx.md de cada requirement). Sacarlas haría el código más "de training", pero menos robusto.
