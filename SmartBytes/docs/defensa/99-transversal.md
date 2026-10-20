# 99 · Transversal: lo que atraviesa todo el proyecto

> **Para qué sirve este documento:** los `DEVx-paso-a-paso.md` explican cada requirement por separado. Acá está lo que se repite en **todos**: el registro de errores, la fábrica de datos de test, cómo están armados los tests, la cobertura, los 3 jobs nocturnos y el mapa completo del proyecto. Al final, el índice de la defensa y 10 preguntas generales.
>
> Los números de línea son del commit `b061a43` (07/10/2026). Si el código cambia, revisarlos.

---

## 0. Índice de la defensa (en orden)

| # | Documento | Qué cubre |
|---|---|---|
| 0 | [00-patrones-base.md](00-patrones-base.md) | Los 5 patrones que se repiten en los 4 triggers (trigger → handler, before/after, bulk, `oldMap`, sin DML repetido) |
| 1 | [DEV1-paso-a-paso.md](DEV1-paso-a-paso.md) | Vencimiento de la Quote (hoy + 30) + recall nocturno de aprobaciones pendientes |
| 2 | [DEV2-paso-a-paso.md](DEV2-paso-a-paso.md) | Activación automática de la Order (before update + Queueable en insert) |
| 3 | [DEV3-paso-a-paso.md](DEV3-paso-a-paso.md) | Renewal Opportunity al activar el Contract + Renewal Quote 30 días antes + email |
| 4 | [DEV4-paso-a-paso.md](DEV4-paso-a-paso.md) | Contador de Subscriptions activas en el Contract |
| 5 | [DEV5-paso-a-paso.md](DEV5-paso-a-paso.md) | Barra de progreso de la Quote (LWC + controller) |
| 6 | **99-transversal.md** (este) | Error Log, TestDataFactory, tests, cobertura, jobs, mapa, preguntas generales |

Material de apoyo: [docs/code-review/](../code-review/) (un `DEVx.md` completo por requirement + [PREGUNTAS-REVISOR.md](../code-review/PREGUNTAS-REVISOR.md)), [BUILD-TRACKER.md](../BUILD-TRACKER.md) y [qa-pending.md](../qa-pending.md).

---

## 1. `ErrorLogUtil` y `Error_Log__c`

### Por qué existe

Casi todo nuestro código corre **sin un usuario mirando**: un Queueable (DEV #2), tres Batches nocturnos (DEV #1, #3, #4) y un envío de emails (DEV #3). Si algo falla ahí, no hay pantalla roja para nadie. Teníamos dos opciones malas y una buena:

| Opción | Qué pasa | Por qué no / por qué sí |
|---|---|---|
| Dejar que la excepción explote | Rollback de **toda** la transacción: si falla 1 Order de 200, no se activa ninguna | ❌ Un registro malo frena a todos |
| `try/catch` vacío o `Database.update(list, false)` sin mirar el resultado | Los buenos se guardan, los malos fallan **en silencio** | ❌ Nadie se entera; el training pide "sin fallar en silencio" |
| `Database.update(list, false)` + guardar cada error en un objeto | Los buenos se guardan, y cada falla queda registrada con clase, registro y mensaje | ✅ Lo elegido |

Alternativas descartadas: `System.debug` (solo se ve si alguien tenía un debug log prendido justo en ese momento), mandar un email por error (gasta el límite de emails y llena casillas), Platform Events (fuera del training).

### Qué guarda en `Error_Log__c`

| Campo | Tipo | Qué tiene |
|---|---|---|
| `Name` | Auto Number ("Error Log Number") | Número del log |
| `Class_Name__c` | Text(255) | Clase donde falló (constante `CLASS_NAME` de cada clase) |
| `Record_Id__c` | Text(18) | Id del registro que falló (texto, no lookup: el log puede ser de una Order, un Contract, una Quote… y un lookup solo apunta a un objeto) |
| `Error_Message__c` | Long Text Area | Prefijo de la operación + `StatusCode` + mensaje (ej. `Order activation failed: FIELD_CUSTOM_VALIDATION_EXCEPTION - ...`) |

Quién **ve** los logs lo controla el permission set `Error_Log_Access`.

### Los 3 métodos — [ErrorLogUtil.cls](../../force-app/main/default/classes/ErrorLogUtil.cls)

| Método | Líneas | Qué hace |
|---|---|---|
| `buildLog( className, recordId, errorMessage )` | [17-23](../../force-app/main/default/classes/ErrorLogUtil.cls#L17-L23) | Arma el `Error_Log__c` **en memoria** (sin DML). Se puede llamar adentro de un loop sin problema |
| `saveLogs( errorLogList )` | [33-38](../../force-app/main/default/classes/ErrorLogUtil.cls#L33-L38) | Un solo `insert` de toda la lista (si está vacía, no hace nada). Usa `AccessLevel.SYSTEM_MODE`: el log es un registro del sistema y se tiene que guardar aunque el usuario que disparó el proceso no tenga permisos sobre `Error_Log__c` (si fallara el log, cancelaría justo el proceso que queríamos proteger) |
| `saveLogsForFailedResults( saveResultList, recordList, className, prefix )` | [53-65](../../force-app/main/default/classes/ErrorLogUtil.cls#L53-L65) | Recorre los `SaveResult` de un `Database.update(list, false)`, arma un log por **cada** error de cada registro fallido (buscándolo por posición `i`, porque un resultado fallido no tiene Id) y los guarda con un solo insert |

El patrón es siempre "**armar adentro del loop, guardar una vez afuera**": nunca DML dentro de un for.

### Dónde se usa

| Archivo:línea | DEV | Qué registra | Método |
|---|---|---|---|
| [OrderTriggerHandler.cls:112-115](../../force-app/main/default/classes/OrderTriggerHandler.cls#L112-L115) | #2 | Se llegó al límite de Queueables y la Order no se pudo encolar para activarse | `buildLog` + `saveLogs` |
| [OrderActivationQueueable.cls:52-54](../../force-app/main/default/classes/OrderActivationQueueable.cls#L52-L54) | #2 | Una Order que no se pudo activar | `saveLogsForFailedResults` |
| [QuoteExpirationBatch.cls:106-116](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L106-L116) | #1 | Un recall de aprobación que falló (`Approval.ProcessResult`, no `SaveResult`, por eso usa `buildLog`) | `buildLog` + `saveLogs` |
| [ActiveSubscriptionCounter.cls:146-147](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L146-L147) | #4 | Un Contract al que no se le pudo guardar el recuento | `saveLogsForFailedResults` |
| [RenewalQuoteBatch.cls:102-111](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L102-L111) | #3 | Un Contract al que no se le pudo tildar `RenewalQuoted` | `saveLogsForFailedResults` |
| [RenewalQuoteBatch.cls:141-142](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L141-L142) | #3 | Una Renewal Opportunity que no pasó a Proposal/Price Quote | `saveLogsForFailedResults` |
| [QuoteTriggerHandler.cls:201-216](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L201-L216) | #3 | Un email de Renewal Quote que falló (`SendEmailResult`) o una excepción del envío (`catch`, ej. Deliverability apagado) | `buildLog` + `saveLogs` |

Test propio: [ErrorLogUtilTest.cls](../../force-app/main/default/classes/ErrorLogUtilTest.cls) (4 tests: guarda varios logs, lista vacía no hace DML, un log por cada error fallido, y no registra nada si todo salió bien).

### Por qué no fallamos en silencio (en una frase para el revisor)

"Usamos `allOrNone = false` para que un registro malo no frene a los buenos, pero **cada** falla queda en `Error_Log__c` con la clase, el Id y el StatusCode; así el admin la encuentra con un list view en vez de enterarse por un usuario enojado."

---

## 2. `TestDataFactory`

### Por qué existe (DRY)

Las 13 test classes necesitan Accounts, Contracts, Orders, Quotes… Sin factory, cada una tendría su propio bloque de "armar una Order con todos los campos obligatorios", copiado 5 veces. Si mañana se agrega un campo obligatorio a Order, habría que tocar 5 archivos; con la factory, se toca **uno**.

Está anotada `@IsTest`: no cuenta para la cobertura ni se puede llamar desde código productivo.

### Dos tipos de métodos

- **`create...`** arman **e insertan** (cuando el test solo necesita que el registro exista).
- **`build...`** solo arman **en memoria**, sin insert: el test decide cuándo insertar (por ejemplo, adentro de `Test.startTest()`, o después de cambiar un campo).

| Método | Tipo | Para qué |
|---|---|---|
| `createAccount()` | create | Account básica |
| `createOpportunity( accountId, stageName )` | create | Opportunity en la etapa pedida |
| `createProduct()` | create | Product2 activo |
| `createPricebookEntry()` | create | Producto + precio en el Pricebook estándar (`Test.getStandardPricebookId()`) |
| `createDraftContract( accountId )` | create | Contract en Draft, 12 meses desde hoy |
| `createContract( accountId, startDate, contractTerm )` | create | Contract en Draft con fechas a medida (term `null` = sin fin) |
| `buildContracts( accountId, startDate, contractTerm, n )` | build | N Contracts en Draft (Salesforce no deja insertar uno ya Activated) |
| `buildRenewalOpportunities( accountId, contractList, stageName )` | build | Una Renewal Opportunity por Contract, igual a las de CPQ |
| `buildSubscriptions( contractId, productId, n, quantity )` | build | N Subscriptions (cantidad negativa = baja de Amendment) |
| `buildOrders( accountId, n, priceCalcStatus )` | build | N Orders Draft con el Price Calc Status pedido |
| `buildOrderItems( orderList, pricebookEntry )` | build | Un Order Product por Order |
| `buildQuotes( accountId, n, status, expirationDate )` | build | N Quotes con estado y vencimiento a medida |
| `buildQuoteLines( quoteId, productId, n )` | build | N Quote Lines |
| `buildQuoteDocument( quoteId, opportunityId )` | build | Un Quote Document de CPQ |

Todos los `build` reciben un **número de registros**: con el mismo método se arma 1 registro para el test positivo y 200 para el bulk.

---

## 3. Cómo están armados los tests

Ejemplo de referencia: [OrderTriggerHandlerTest.cls](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls).

| Pieza | Qué es | Por qué |
|---|---|---|
| `@IsTest private class XTest` | Clase de test, una por clase productiva | Convención del training (Módulo 3) |
| `@testSetup static void setup()` | Corre **una vez** antes de los tests de la clase; cada test arranca con una copia de esos datos | Ahorra tiempo y DML: el Account y el producto se crean una sola vez, no 11 |
| `Test.startTest()` / `Test.stopTest()` | Abre una "caja" con **governor limits nuevos**; al cerrarla, Salesforce ejecuta **ya** todo lo async encolado (Queueable, Batch, Scheduled) | Sin `stopTest`, el Queueable del DEV #2 o los Batches nunca correrían dentro del test y el assert vería la Order en Draft |
| `System.assertEquals( esperado, real, 'mensaje' )` | Assert con mensaje en **todos** los tests | Si falla, el mensaje dice qué se esperaba en lenguaje de negocio, no solo "expected 200 but was 0" |
| Valores literales en los asserts (`'Activated'`, `'0 0 1 * * ?'`) | No se compara contra la constante de la clase | Comparar con la constante es compararla consigo misma: si la constante está mal, el test igual pasa |
| `BULK_SIZE = 200` | Constante en cada test class con caso bulk | 200 es el tamaño de un lote de trigger: prueba que no hay SOQL/DML en loops |

### Positivo, negativo y bulk

Cada test class cubre los 3 tipos (ej. DEV #2):

- **Positivo:** `activateOnInsertTest` — una Order con `Not Needed` y productos queda Activated.
- **Negativo:** `notActivatedOnInsertWhenNotReadyTest` (estado `Queued`) y `notActivatedOnInsertWithoutItemsTest` (sin productos) — no se activa.
- **Bulk:** `activateOnInsertBulkTest` — 200 Orders se activan con **un solo** Queueable.

Excepciones justificadas: los 3 tests de Schedulers (solo verifican cron + que se lanza el Batch) y `QuoteProgressControllerTest` (sin bulk: la página muestra **una** Quote).

En los Batches, `execute()` corre **una sola vez** en un test: por eso el bulk usa 200 registros, el tamaño de un chunk.

### `SBQQ.TriggerControl.disable()` — solo donde hace falta

Es una API del paquete CPQ (fuera del training) que **apaga los triggers de CPQ** dentro del test. Se usa en 3 lugares, cada uno con su comentario explicando por qué:

| Test | Por qué |
|---|---|
| [ContractTriggerHandlerTest.cls:50](../../force-app/main/default/classes/ContractTriggerHandlerTest.cls#L50) (`activationBulkTest`) | Activar 200 Contracts hace que CPQ genere 200 Renewal Opportunities y rompa `Too many SOQL queries: 101` **dentro de su código**. Nuestro trigger usa 0 queries |
| [RenewalQuoteBatchTest.cls:181](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L181) (`bulkTest`) | Lo mismo con 200 Renewal Quotes. Por eso además el job real corre de a 1 |
| [QuoteProgressControllerTest.cls:72-75](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L72-L75) | Solo para **armar el dato**: tildar `Ordered` haría que CPQ cree una Order real. Se apaga y se vuelve a prender (`enable()`) antes de probar el controller |

La idea para defender: **el bulk prueba NUESTRO código con 200 registros**; lo que genera CPQ se probó en el org y en los tests no-bulk, que corren con CPQ prendido.

### Scheduler tests: nombre de job propio

Los jobs programados **no se aíslan** en los tests: si el test hace `System.schedule` con el mismo nombre que el job real del org, falla con "already scheduled" y rompe todos los deploys. Por eso los 3 tests usan `JOB_NAME + ' (Test)'` ([QuoteExpirationSchedulerTest.cls:18](../../force-app/main/default/classes/QuoteExpirationSchedulerTest.cls#L18)).

---

## 4. Cobertura actual

**Corrida:** 07/10/2026 20:33 UTC, Test Run `707fj000017G578`, todos los tests locales (`sf apex run test --test-level RunLocalTests --code-coverage`).

**Resultado:** **85 métodos, 85 pasan, 0 fallan** (Salesforce informa 94 porque cuenta los 9 `@testSetup` como un resultado más).
**Cobertura total del org: 97%** (363 de 373 líneas). Objetivo del Final Assignment: ≥ 85% ✅. Mínimo por clase: 91%.

| Clase / Trigger | DEV | Líneas cubiertas | Cobertura |
|---|---|---|---|
| OrderTrigger | #2 | 4 / 4 | 100% |
| OrderTriggerHandler | #2 | 51 / 51 | 100% |
| OrderActivationQueueable | #2 | 16 / 16 | 100% |
| ErrorLogUtil | transversal | 19 / 19 | 100% |
| QuoteTrigger | #1 / #3 | 6 / 6 | 100% |
| QuoteTriggerHandler | #1 / #3 | 64 / 70 | **91%** |
| QuoteExpirationBatch | #1 | 28 / 30 | **93%** |
| QuoteExpirationScheduler | #1 | 2 / 2 | 100% |
| SubscriptionTrigger | #4 | 8 / 8 | 100% |
| SubscriptionTriggerHandler | #4 | 35 / 35 | 100% |
| ActiveSubscriptionCounter | #4 | 45 / 45 | 100% |
| ActiveSubscriptionRecountBatch | #4 | 8 / 8 | 100% |
| ActiveSubscriptionRecountScheduler | #4 | 2 / 2 | 100% |
| ContractTrigger | #3 | 2 / 2 | 100% |
| ContractTriggerHandler | #3 | 8 / 8 | 100% |
| RenewalQuoteBatch | #3 | 35 / 37 | **95%** |
| RenewalQuoteScheduler | #3 | 3 / 3 | 100% |
| QuoteProgressController | #5 | 27 / 27 | 100% |

`TestDataFactory` no aparece: es `@IsTest` y no cuenta para la cobertura. El LWC `quoteProgress` tampoco (Apex no mide JavaScript; se probó en el org).

**Las 10 líneas sin cubrir son todas ramas de error** que no se pueden forzar con datos de test:

- `QuoteTriggerHandler` (6): un email que falla y el `catch` del envío. En un test no se puede hacer fallar `Messaging.sendEmail`.
- `QuoteExpirationBatch` (2): el Error Log cuando un recall falla.
- `RenewalQuoteBatch` (2): `return` de seguridad (fallaron todos los updates, o no hay Opportunity en Prospecting).

Detalle por test class en [BUILD-TRACKER.md](../BUILD-TRACKER.md).

---

## 5. Los 3 jobs programados

| Job | Clase Schedulable → Batch | Cron | Hora (America/Los_Angeles) | Qué hace | DEV |
|---|---|---|---|---|---|
| Quote Expiration Recall - Nightly | `QuoteExpirationScheduler` → `QuoteExpirationBatch` | `0 0 1 * * ?` | 1:00 | Quotes **In Review** vencidas (`ExpirationDate <= hoy`) con Opportunity no ganada → recall de la aprobación pendiente (vuelven a Draft) | #1 |
| Active Subscriptions Recount - Nightly | `ActiveSubscriptionRecountScheduler` → `ActiveSubscriptionRecountBatch` | `0 0 2 * * ?` | 2:00 | Recuenta `Active_Subscriptions__c` de los Contracts, para lo que empieza o vence **por fecha** (sin que nadie toque la Subscription, el trigger no se entera) | #4 |
| Renewal Quote Generation - Nightly | `RenewalQuoteScheduler` → `RenewalQuoteBatch` (chunk de **1**) | `0 0 3 * * ?` | 3:00 | Contracts Activated que vencen en ≤ 30 días → tilda `RenewalQuoted` (CPQ crea la Renewal Quote) y pasa la Renewal Opportunity a Proposal/Price Quote | #3 |

Cron: `segundos minutos horas día-del-mes mes día-de-la-semana`. `0 0 1 * * ?` = "a las 1:00:00 todos los días". Están en horas distintas para no competir por los mismos registros ni por los límites async.

Cada Scheduler solo hace `Database.executeBatch(...)`: la lógica vive en el Batch (regla del Módulo 4: no poner lógica en el `execute()` del Schedulable). `JOB_NAME` y `CRON_EXPRESSION` son constantes de cada Scheduler.

Estado verificado hoy (07/10/2026) en el org: los 3 en **WAITING**, CronTrigger `08efj00000e3dhG` (1:00), `08efj00000e3dhH` (2:00), `08efj00000e3dhI` (3:00).

### Cómo verlos en Setup

- **Setup → Scheduled Jobs:** los 3 por nombre, con próxima ejecución, quién los programó y botón *Delete*.
- **Setup → Apex Jobs:** cada ejecución del Batch (Completed / Failed, cuántos lotes, errores).
- **Error Logs** (tab del objeto): lo que haya fallado por registro.
- Por consola: `sf data query --query "SELECT CronJobDetail.Name, CronExpression, State, NextFireTime FROM CronTrigger WHERE CronJobDetail.JobType = '7'"` (`7` = Scheduled Apex).

### Cómo se reprograman después de un deploy

Salesforce **no deja redeployar** una clase que usa un job pendiente ("This schedulable class has jobs pending"), ni las clases que esa clase llama (Scheduler → Batch → `ErrorLogUtil`). Procedimiento usado en el congelamiento y en la revisión de calidad (05/10/2026), sin activar el bypass de Deployment Settings:

1. **Abortar** los 3 jobs (Apex anónimo): `System.abortJob( id )` de cada `CronTrigger`, buscándolos por nombre.
2. **Dry-run** del deploy con `RunLocalTests` (valida y corre los tests sin aplicar nada).
3. **Quick deploy**: `sf project deploy quick --job-id <id del dry-run>` (aplica la validación sin volver a correr los tests).
4. **Reprogramar** como frandev, con las constantes de cada clase:
   ```apex
   System.schedule( QuoteExpirationScheduler.JOB_NAME, QuoteExpirationScheduler.CRON_EXPRESSION, new QuoteExpirationScheduler() );
   System.schedule( ActiveSubscriptionRecountScheduler.JOB_NAME, ActiveSubscriptionRecountScheduler.CRON_EXPRESSION, new ActiveSubscriptionRecountScheduler() );
   System.schedule( RenewalQuoteScheduler.JOB_NAME, RenewalQuoteScheduler.CRON_EXPRESSION, new RenewalQuoteScheduler() );
   ```
5. Verificar en *Scheduled Jobs* que estén los 3. Los jobs quedan iguales; solo cambia el Id del CronTrigger.

Hacerlo lejos de la 1:00 (hora del org). Si el deploy solo toca clases que **no** usan ningún job (ej. `QuoteProgressController`), no hace falta abortar nada: se despliegan solo los archivos cambiados.

---

## 6. Mapa general del proyecto

| Objeto | Trigger (contextos) | Handler | Clases auxiliares | Test classes | DEV |
|---|---|---|---|---|---|
| `Order` | `OrderTrigger` (before update, after insert) | `OrderTriggerHandler` | `OrderActivationQueueable`, `ErrorLogUtil` | `OrderTriggerHandlerTest` | #2 |
| `SBQQ__Quote__c` | `QuoteTrigger` (before insert, before update, after insert) | `QuoteTriggerHandler` (vencimiento hoy + 30 en before; email de Renewal en after insert) | `ErrorLogUtil` | `QuoteTriggerHandlerTest` | #1 A, #3 parte 3 |
| `SBQQ__Quote__c` (nocturno) | — | — | `QuoteExpirationScheduler` → `QuoteExpirationBatch`, `ErrorLogUtil` | `QuoteExpirationSchedulerTest`, `QuoteExpirationBatchTest` | #1 B |
| `SBQQ__Subscription__c` → `Contract` | `SubscriptionTrigger` (after insert, update, delete, undelete) | `SubscriptionTriggerHandler` | `ActiveSubscriptionCounter`, `ErrorLogUtil` | `SubscriptionTriggerHandlerTest`, `ActiveSubscriptionCounterTest` | #4 |
| `Contract` (nocturno, recuento) | — | — | `ActiveSubscriptionRecountScheduler` → `ActiveSubscriptionRecountBatch` → `ActiveSubscriptionCounter` | `ActiveSubscriptionRecountSchedulerTest`, `ActiveSubscriptionRecountBatchTest` | #4 |
| `Contract` | `ContractTrigger` (before update) | `ContractTriggerHandler` | — (constante `STATUS_ACTIVATED` reusada por `RenewalQuoteBatch`) | `ContractTriggerHandlerTest` | #3 parte 1 |
| `Contract` + Renewal `Opportunity` (nocturno) | — | — | `RenewalQuoteScheduler` → `RenewalQuoteBatch`, `ErrorLogUtil` | `RenewalQuoteSchedulerTest`, `RenewalQuoteBatchTest` | #3 parte 2 |
| `SBQQ__Quote__c` (UI) | — | — | `QuoteProgressController` (`@AuraEnabled`) + LWC `quoteProgress` en `Training_Quote_Page` | `QuoteProgressControllerTest` | #5 |
| `Error_Log__c` | — | — | `ErrorLogUtil` (usado por 6 clases) | `ErrorLogUtilTest` | transversal |
| (todos) | — | — | `TestDataFactory` (`@IsTest`) | usada por todas | transversal |

Encaje con el IC: `Opportunity → Closed Won` → Flow 1 (Quote Ordered) → CPQ crea la Order → **DEV #2** la activa → Flow 2 la contrata → CPQ crea Contract + Subscriptions (**DEV #4** cuenta) → activación manual del Contract (**DEV #3** parte 1) → 30 días antes del fin (**DEV #3** parte 2 y 3). **DEV #1** acompaña la aprobación de la Quote y **DEV #5** muestra todo el recorrido.

**Totales:** 4 triggers (uno por objeto), 4 handlers, 3 Schedulers, 3 Batches, 1 Queueable, 1 controller + 1 LWC, 2 utilitarias (`ErrorLogUtil`, `ActiveSubscriptionCounter`), 1 factory, 13 test classes.

---

## 7. 10 preguntas generales del revisor

**1. ¿Cómo garantizan que todo está bulkificado?**
Ninguna SOQL ni DML adentro de un for: juntamos Ids en un `Set`, hacemos una query con `IN :set`, armamos un `Map` y al final un solo update. Y lo probamos: cada trigger y cada Batch tiene un test con 200 registros que pasa sin romper límites.

**2. ¿Por qué un trigger por objeto y sin lógica?**
Con dos triggers en el mismo objeto Salesforce no garantiza el orden en que corren. Con uno solo, el orden lo decide el trigger, y la lógica en el handler se puede leer, testear y reusar. El trigger solo mira el contexto y delega.

**3. ¿Cómo eligieron before o after en cada caso?**
Before cuando cambiamos campos del **mismo** registro (fecha de la Quote, Status de la Order, flag del Contract): no hace falta DML, Salesforce lo guarda solo. After cuando tocamos **otros** registros o necesitamos el Id: recuento en el Contract (DEV #4), encolar el Queueable de la Order (DEV #2), email de la Renewal Quote (DEV #3).

**4. ¿Qué pasa si falla un registro de 200?**
Usamos `Database.update(list, false)`: los 199 buenos se guardan y el malo queda en `Error_Log__c` con su Id, clase y StatusCode, vía `ErrorLogUtil`. No hay rollback de todo ni falla silenciosa.

**5. ¿Por qué hay código asíncrono (Queueable, Batch, Scheduled)?**
Cada uno por una razón concreta: el Queueable porque la Order de CPQ nace sin productos y hay que activarla después (DEV #2); los Batch + Scheduled porque hay cosas que pasan **por fecha**, sin que nadie edite un registro (vencimiento, Subscriptions que empiezan o terminan, contratos a 30 días del fin), y un trigger no se entera de eso.

**6. ¿Por qué usaron campos y APIs de CPQ en vez de crear los registros a mano?**
CPQ ya sabe armar Renewal Opportunities y Quotes con precios, Amendments combinados y fechas correctas. Tildar `SBQQ__RenewalForecast__c` / `SBQQ__RenewalQuoted__c` reutiliza esa lógica; crearlos a mano sería reescribir CPQ y quedaría desincronizado.

**7. ¿Cómo evitan reprocesar registros que no cambiaron?**
Comparamos `Trigger.new` con `Trigger.oldMap`: la lógica corre solo si el campo **pasó** al valor que nos interesa (Approved, Activated, Completed/Not Needed). En DEV #4 solo recontamos si cambió un campo que afecta el conteo.

**8. ¿Cómo llegaron a 85%+ de cobertura y qué queda sin cubrir?**
Tests positivos, negativos y bulk para cada clase, con datos de una `TestDataFactory` compartida. Lo único sin cubrir son ramas de error que no se pueden forzar en un test (que falle `Messaging.sendEmail`, que falle un recall, `return` de seguridad). Están listadas en el Build Tracker.

**9. ¿Por qué apagan los triggers de CPQ en algunos tests? ¿No es hacer trampa?**
Solo en 3 lugares y con comentario. En los 2 bulk, CPQ rompe el límite de 101 queries **dentro de su propio código** con 200 registros; nuestro código no. El test prueba nuestra bulkificación; lo de CPQ se probó en el org y en los tests no-bulk, que corren con CPQ prendido. En el tercero es solo para armar un dato.

**10. ¿Qué cuidado hay que tener al deployar este proyecto?**
Las clases que usan los 3 jobs nocturnos no se pueden redeployar con los jobs pendientes. Se abortan los jobs, se hace dry-run con `RunLocalTests`, quick deploy y se reprograman con las constantes `JOB_NAME` / `CRON_EXPRESSION` de cada Scheduler. Y los tests de Schedulers usan un nombre de job propio para no chocar con el real.
