# DEV #4 · Paso a paso para la defensa (contador de Subscriptions activas en el Contract)

> **Para qué sirve este documento:** es la guía para **mostrar y explicar** el DEV #4 en el Code Review, en el orden en que se ejecuta. El detalle completo (diseño, bloques, 13 preguntas, Build Tracker) está en [`docs/code-review/DEV4.md`](../code-review/DEV4.md). Acá no se repite, se referencia. Los patrones que se repiten en todos los DEV están en [`00-patrones-base.md`](00-patrones-base.md).
>
> Los números de línea son del commit `1ae7a77` (07/10/2026). Si el código cambia, revisarlos.

---

## 1. Requirement en 2 líneas (palabras de vendedor)

- "Cuando abro un Contract quiero ver **de un vistazo** cuántas suscripciones tiene vigentes **hoy** el cliente, sin abrir la related list y contar a mano."
- "Y si le agrego o le saco usuarios con un Amendment, el número tiene que seguir diciendo cuántas **suscripciones** tiene, no cuántos registros armó CPQ por atrás."

Texto original y tabla de partes (A)…(D): [DEV4.md §1](../code-review/DEV4.md#1-qué-pide-el-requirement).

---

## 2. Flujo lógico (sin código)

1. El número vive en un campo del Contract (`Active_Subscriptions__c`), pero **lo que cambia son las Subscriptions**: por eso el disparador está en `SBQQ__Subscription__c`.
2. **No se puede usar un Roll-Up Summary**: la relación Subscription → Contract es **Lookup** (los Roll-Up solo existen en Master-Detail), es un campo del paquete que no podemos cambiar y además un Roll-Up no puede filtrar por "hoy".
3. Cada vez que una Subscription **se crea, se edita (algo que importe), se borra o se recupera**, el trigger arma la lista de Contracts afectados y los **recuenta desde cero** (no suma ni resta 1).
4. "Activa" = **vigente hoy**: ya empezó, no venció y no fue terminada. El estado del Contract no se mira (supuesto confirmado).
5. Los Amendments **no inflan** el número: CPQ crea una Subscription nueva por la diferencia (+100, −10) que apunta a la **original**; sumamos las cantidades por original y contamos **una** por cada original con neto > 0.
6. Pero hay cambios que **nadie guarda**: una Subscription que vence o que empieza por fecha. Para eso hay un **job nocturno a las 2:00** que recuenta todos los Contracts.
7. Trigger y job usan **la misma clase** (`ActiveSubscriptionCounter`): la regla de "activa" está escrita en un solo lugar (DRY).

---

## 3. Cronología demo → código

### Vista general

```
CAMINO 1 (alguien guarda una Subscription)              CAMINO 2 (pasa el tiempo)
Usuario / CPQ: insert · update · delete · undelete      2:00 · ActiveSubscriptionRecountScheduler
  └─ SubscriptionTrigger (AFTER, los 4 contextos)          └─ ActiveSubscriptionRecountBatch (tandas de 200)
       └─ SubscriptionTriggerHandler                            └─ execute: Set<Id> de la tanda
            └─ Set<Id> de Contracts a recontar                       │
                 └──────────────┬────────────────────────────────────┘
                                ▼
              ⭐ ActiveSubscriptionCounter.recountActiveSubscriptions
                 1 SOQL (Contract + subquery) → isInForceToday → Map por original
                 → countActiveSubscriptions → update SOLO si cambió (1 DML)
```

### Caso real del QA: Contract 00000112 ("QA Demo Corp", 07/10/2026)

Antes de la tabla, el caso que vas a mostrar. Así quedó en el org (consultado el 07/10/2026):

| Subscription | Producto | Cantidad | Revisa a | Inicio | ¿Vigente hoy? |
|---|---|---|---|---|---|
| SUB-0000021…28 | 8 productos del contracting original (Cloud Core, **Monthly Named Users 125**, Disaster Recovery, Clustering, App Monitoring, Event Mgmt, Paid Data Plan, **Premium Success Plan 1**) | 1 / 125 | — (son originales) | 06/10/2026 | ✅ |
| SUB-0000029 | Monthly Named Users | **+100** | SUB-0000022 | 06/04/2027 | ❌ futura |
| SUB-0000030 | Premium Success Plan | 0 | SUB-0000028 | 06/04/2027 | ❌ futura |
| SUB-0000031 | Monthly Named Users | **−10** | SUB-0000022 | 06/07/2027 | ❌ futura |
| SUB-0000032 | Premium Success Plan | 0 | SUB-0000028 | 06/07/2027 | ❌ futura |

- **12 registros, campo = 8.** (Si contás "10", te faltan las dos revisiones con cantidad 0: CPQ las crea porque Premium Success Plan es **Percent Of Total**, su precio depende del total y cambia cuando cambian los usuarios.)
- **Hoy:** las 4 revisiones arrancan en el futuro → `isInForceToday` las descarta → quedan las 8 originales → **8**.
- **En abril y julio de 2027**, cuando empiecen: se suman a su original → Monthly Named Users = 125 + 100 − 10 = **215 > 0** → cuenta 1; Premium Success Plan = 1 + 0 + 0 = **1 > 0** → cuenta 1. **Sigue en 8.**
- **Contando registros** daría 12 (o 10 sin las de cantidad 0): eso no es lo que pregunta un vendedor.
- **Evidencia de que lo hizo el trigger en vivo:** los 3 `QueueableContractOrdersClient` de CPQ (contracting + 2 Amendments, 15:24 / 16:18 / 16:27 UTC) terminaron **Completed, 0 errores**, el job nocturno había corrido a las 9:00 UTC (**antes**) y hay **0** Error Logs. O sea: el 8 lo puso `SubscriptionTrigger` **dentro** del contracting de CPQ. Esto es lo que pedía **QA-DEV4-01** ([qa-pending.md](../qa-pending.md)).

### Camino 1-A: CPQ contrata / hace un Amendment → **after insert**

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | Amendment: Quote **Ordered** → (DEV #2 activa la Order, Flow 2 la contrata). Espero ~30 s. | CPQ corre `QueueableContractOrdersClient` e **inserta** las Subscriptions nuevas (SUB-0000029/30). | — (código de CPQ) | CPQ no toca la original: crea una por la diferencia, con `SBQQ__RevisedSubscription__c` = la original. | **async** de CPQ |
| 2 | (no se ve) | Insert de Subscriptions → `SubscriptionTrigger`. | [SubscriptionTrigger.trigger:12](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L12), [:13-14](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L13-L14) | Declara los **4 contextos, todos after**. `isAfter && isInsert` → `afterInsert( Trigger.new )`. | **after insert** |
| 3 | (no se ve) | → handler | [SubscriptionTriggerHandler.cls:25-27](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L25-L27) | Entrada `public static` → `getContractIds` → pasa el Set al contador. | after insert |
| 4 | (no se ve) | → juntar Contracts | [SubscriptionTriggerHandler.cls:66-74](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L66-L74) | `Set<Id>` sin repetidos y sin vacíos: si CPQ inserta 2 Subscriptions del mismo Contract, el Contract entra **una** vez. | after insert |
| 5 | (no se ve) | ⭐ → `recountActiveSubscriptions` | [ActiveSubscriptionCounter.cls:42-46](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L42-L46) | Si el Set está vacío → `return` **antes** de la SOQL. | after insert |
| 6 | (no se ve) | → **1 SOQL** | [ActiveSubscriptionCounter.cls:48](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L48), [:53-60](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L53-L60) | `today` una sola vez. Contracts + subquery `SBQQ__Subscriptions__r` (cantidad, original, fechas fórmula, terminación), `WHERE Id IN :contractIdSet`. Como estamos en **after**, la query ya ve las Subscriptions recién insertadas. | after insert |
| 7 | (no se ve) | → ¿vigente hoy? | [ActiveSubscriptionCounter.cls:66-69](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L66-L69) → [:107-116](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L107-L116) | `hasStarted`, `hasNotEnded`, `isNotTerminated`. SUB-0000029 empieza en 2027 → `continue`. | after insert |
| 8 | (no se ve) | → agrupar por la original | [ActiveSubscriptionCounter.cls:62](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L62), [:71-83](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L71-L83) | Clave = `sub.Id` o, si es revisión, `SBQQ__RevisedSubscription__c`. Suma la cantidad en `netQuantityByOriginalIdMap` (null = 0). | after insert |
| 9 | (no se ve) | → contar | [ActiveSubscriptionCounter.cls:86](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L86) → [:125-133](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L125-L133) | Una por cada original con neto **> 0** → **8**. | after insert |
| 10 | (no se ve) | → ¿cambió? | [ActiveSubscriptionCounter.cls:90-93](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L90-L93) | El Contract ya tenía 8 → **no** va a la lista → **0 DML** (no se disparan de gusto los triggers de Contract). | after insert |
| 11 | (no se ve) | → guardar | [ActiveSubscriptionCounter.cls:96](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L96) → [:142-148](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L142-L148) | Lista vacía → `return`. Si hubiera: **1** `Database.update( lista, false )` + `ErrorLogUtil.saveLogsForFailedResults`. Un error **no** tira abajo el contracting de CPQ. | after insert |
| 12 | Refresco el Contract 00000112: **Active Subscriptions = 8**, con 12 registros en la related list. | — | — | Resultado. | — |

> En el contracting original (primer insert de las 8) el paso 10 sí encontró un cambio (0 → 8) e hizo **1** update del Contract. Ese update dispara `ContractTrigger` (DEV #3) en before update, pero el Status no cambió → no hace nada. **Sin recursión**: nosotros escribimos Contract, no Subscription.

### Camino 1-B: edito una Subscription en vivo → **after update**

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | Abro **SUB-0000021** (Cloud Core) → *Terminated Date* = **hoy** → Save. | Update → `SubscriptionTrigger`. | [SubscriptionTrigger.trigger:15-16](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L15-L16) | `afterUpdate( Trigger.new, Trigger.oldMap )`. | **after update** |
| 2 | (no se ve) | → handler | [SubscriptionTriggerHandler.cls:35-38](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L35-L38) | → `getContractIdsWithRelevantChanges`. | after update |
| 3 | (no se ve) | → **¿cambió algo que importe?** | [SubscriptionTriggerHandler.cls:88-92](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L88-L92) → [:111-122](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L111-L122) | `oldMap.get( newSub.Id )` y compara 6 campos **reales** (Contract, Quantity, fechas propias, TerminatedDate, RevisedSubscription). Cambió TerminatedDate → sí. Si hubiera cambiado el precio → `continue` y **0 queries**. | after update |
| 4 | (no se ve) | → Contract nuevo **y** viejo | [SubscriptionTriggerHandler.cls:93-99](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L93-L99) | Agrega el Contract actual y, si se movió, también el anterior (uno pierde, otro gana). | after update |
| 5 | (no se ve) | ⭐ mismo recuento (pasos 5-11 de arriba) | [ActiveSubscriptionCounter.cls:42-97](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L42-L97) | `isNotTerminated`: TerminatedDate = hoy **no** es > hoy → no cuenta → **7** ≠ 8 → 1 update. | after update |
| 6 | Refresco el Contract: **7**. Borro el Terminated Date → **8**. | — | — | Resultado. | — |

### Camino 1-C: borro y recupero → **after delete** / **after undelete**

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | Borro **SUB-0000021** → Delete. | `SubscriptionTrigger` | [SubscriptionTrigger.trigger:17-18](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L17-L18) | `afterDelete( Trigger.old )`: **en delete no existe `Trigger.new`** (sería `null`). El Contract de la borrada solo está en `Trigger.old`. | **after delete** |
| 2 | (no se ve) | → handler | [SubscriptionTriggerHandler.cls:45-47](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L45-L47) | Mismo `getContractIds` (DRY): recibe una lista, no le importa si viene de new u old. | after delete |
| 3 | (no se ve) | ⭐ recuento | [ActiveSubscriptionCounter.cls:53-60](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L53-L60) | En **after** delete la query **ya no ve** la borrada → **7**. (En before delete todavía la vería y contaría 8: por eso after.) | after delete |
| 4 | Contract: **7**. *Recycle Bin* → Restore SUB-0000021. | `SubscriptionTrigger` | [SubscriptionTrigger.trigger:19-20](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L19-L20) → [SubscriptionTriggerHandler.cls:53-55](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L53-L55) | `afterUndelete( Trigger.new )`. No existe "before undelete": undelete es solo after. | **after undelete** |
| 5 | Contract: **8**. | — | — | Resultado. | — |

### Camino 2: el job nocturno de las 2:00 → **async**

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | *Setup → Scheduled Jobs*: **Active Subscriptions Recount - Nightly**, próxima 2:00. (En la demo: Execute Anonymous `Database.executeBatch( new ActiveSubscriptionRecountBatch() );`) | A las 2:00 Salesforce llama al Scheduler. | [ActiveSubscriptionRecountScheduler.cls:13-16](../../force-app/main/default/classes/ActiveSubscriptionRecountScheduler.cls#L13-L16), [:22-24](../../force-app/main/default/classes/ActiveSubscriptionRecountScheduler.cls#L22-L24) | Sin lógica: `JOB_NAME`, cron `0 0 2 * * ?` y `executeBatch`. | **async** · Scheduled |
| 2 | (no se ve) | `start` | [ActiveSubscriptionRecountBatch.cls:24-29](../../force-app/main/default/classes/ActiveSubscriptionRecountBatch.cls#L24-L29) | `SELECT Id FROM Contract` (todos, sin WHERE: corrige números viejos y completa con 0 los anteriores al campo). | async · Batch `start` |
| 3 | (no se ve) | `execute` (1 por tanda de 200) | [ActiveSubscriptionRecountBatch.cls:37-44](../../force-app/main/default/classes/ActiveSubscriptionRecountBatch.cls#L37-L44) | Arma el `Set<Id>` de la tanda y llama ⭐ al **mismo** `recountActiveSubscriptions` ([:43](../../force-app/main/default/classes/ActiveSubscriptionRecountBatch.cls#L43)). Como `today` es otro día, detecta lo que empezó o venció. | async · Batch `execute` (límites propios por tanda) |
| 4 | (no se ve) | `finish` | [ActiveSubscriptionRecountBatch.cls:50-52](../../force-app/main/default/classes/ActiveSubscriptionRecountBatch.cls#L50-L52) | Vacío a propósito (la interfaz lo exige). | async |
| 5 | *Apex Jobs*: `ActiveSubscriptionRecountBatch` **Completed**, 0 errores. Contract 00000112 sigue en **8** (no cambió → 0 DML). | — | — | El día que una Subscription vence sola, acá es donde baja el número. | — |

**Por qué existe el Batch, con un ejemplo:** el Contract 00000112 vence el **05/10/2027**. Ese día nadie va a editar ninguna Subscription, así que el trigger **no se entera**. Sin el Batch, el campo diría 8 para siempre. La noche del 06/10/2027 el Batch recuenta: ninguna está vigente → **0**. Lo mismo pasa al revés: el 06/04/2027 empieza el +100 (en este caso no cambia el número porque se agrupa, pero si fuera un producto **nuevo** agregado por Amendment con fecha futura, ese día sumaría 1).

---

## 4. Qué decir (guion mientras muestro el código)

1. "El campo está en el Contract, pero lo que cambia son las Subscriptions, y la relación es un **Lookup** del paquete de CPQ: no hay Roll-Up Summary posible, y aunque lo hubiera no puede filtrar por 'hoy'. Por eso es un trigger en `SBQQ__Subscription__c`."
2. "El trigger escucha los **cuatro** contextos y todos son **after**: modifico otro registro, el Contract, y la query tiene que ver el cambio ya guardado. En **delete** uso `Trigger.old`, porque `Trigger.new` no existe, y en after la borrada ya no aparece en la query."
3. "El handler solo decide **qué** Contracts recontar: un `Set<Id>`, y en update comparo con `Trigger.oldMap` para no recontar si cambió algo que no importa, como el precio. Si la Subscription cambia de Contract, recuento los dos."
4. "El recuento está en `ActiveSubscriptionCounter`: 1 SOQL con subquery, 'activa' es vigente hoy, y los Amendments se suman a su Subscription original. Este Contract tiene 12 registros y muestra 8, porque el +100 y el −10 son cambios de cantidad de **una** suscripción, no suscripciones nuevas."
5. "Recuento desde cero y solo hago update si el número cambió: no se desfasa nunca y no disparo triggers de más. Un error va a `Error_Log__c` sin romper el contracting de CPQ."
6. "Y como una Subscription puede vencer sin que nadie la toque, a las 2:00 corre un Batch que llama al **mismo** método. La regla de 'activa' está escrita una sola vez."

---

## 5. Decisiones y alternativas (resumen)

- **Trigger en Subscription + recuento desde cero** en lugar de Roll-Up Summary (imposible: Lookup), Flow o contador incremental `+1/−1` (se desfasa con el primer error).
- **Todo en after**, con una clase compartida `ActiveSubscriptionCounter` (DRY entre trigger y Batch) y **Batch + Scheduler a las 2:00** para lo que cambia por fecha.
- **Opción C para Amendments** (una por original con neto > 0) y **sin mirar el estado del Contract** (supuestos confirmados el 02/10/2026).

Detalle con "por qué sí / por qué no / qué pasaría", incluidas las decisiones chicas (Set vs List, `Map<Id, Decimal>`, `Database.update( lista, false )`, for sobre la subquery): [DEV4.md §2](../code-review/DEV4.md#2-diseño-elegido).

### Dónde aparecen los patrones base en este DEV

Explicación general de cada patrón: [00-patrones-base.md](00-patrones-base.md).

| Patrón | Dónde aparece en el DEV #4 |
|---|---|
| **Un trigger por objeto → handler** | [SubscriptionTrigger.trigger:12-22](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L12-L22): solo variables de contexto y llamadas a `SubscriptionTriggerHandler`. Entradas `public static` ([SubscriptionTriggerHandler.cls:25-55](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L25-L55)) → lógica `private static` ([:66-122](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L66-L122)). Ver [00-patrones-base §1](00-patrones-base.md#1-un-solo-trigger-por-objeto-sin-lógica-trigger--handler). |
| **`Trigger.oldMap` / detectar el cambio real** | [SubscriptionTriggerHandler.cls:89-92](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L89-L92) y [:111-122](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L111-L122). Y `Trigger.old` en delete ([SubscriptionTrigger.trigger:18](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L18)). Ver [00-patrones-base §2](00-patrones-base.md#2-triggernew-triggeroldmap-y-cómo-detectamos-un-cambio-real). |
| **Contexto correcto (after = registro relacionado + DML)** | Los 4 contextos son after ([SubscriptionTrigger.trigger:12](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L12)); el DML es sobre Contract ([ActiveSubscriptionCounter.cls:146](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L146)). Ver [00-patrones-base §3](00-patrones-base.md#3-before-vs-after-cuándo-uso-cada-uno). |
| **Bulkificación: Set, 1 SOQL, nada en loops** | `Set<Id>` ([SubscriptionTriggerHandler.cls:67](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L67), [:87](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L87)); **1** SOQL con subquery ([ActiveSubscriptionCounter.cls:53-60](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L53-L60)); **1** DML con lista ([:146](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L146)); `Map<Id, Decimal>` ([:62](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L62)). Ver [00-patrones-base §4](00-patrones-base.md#4-bulkificación-setsmaps-soql-y-dml-fuera-de-loops). |
| **Condicional antes de la SOQL / DML** | [ActiveSubscriptionCounter.cls:44-46](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L44-L46) (Set vacío → 0 queries) y [:143-145](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L143-L145) (nada que actualizar → 0 DML). |
| **WHERE para reducir volumen** | [ActiveSubscriptionCounter.cls:59](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L59). (El `start` del Batch **no** tiene WHERE a propósito: ver DEV4.md §2.) |
| **Subquery para hijos** | `SBQQ__Subscriptions__r` en [ActiveSubscriptionCounter.cls:55-57](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L55-L57), recorrida con `for` ([:66](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L66)) para no fallar con más de 200 hijos. |
| **DRY** | `ActiveSubscriptionCounter` lo usan el handler ([SubscriptionTriggerHandler.cls:26](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L26), [:36](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L36), [:46](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L46), [:54](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L54)) y el Batch ([ActiveSubscriptionRecountBatch.cls:43](../../force-app/main/default/classes/ActiveSubscriptionRecountBatch.cls#L43)). `getContractIds` sirve para insert, delete y undelete. `ErrorLogUtil.saveLogsForFailedResults` compartido con DEV #2 y #3 ([ActiveSubscriptionCounter.cls:147](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L147)). |
| **Recursión cortada por "no cambió"** | Update solo si el número cambió ([ActiveSubscriptionCounter.cls:90](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L90)); el `ContractTrigger` (DEV #3) no hace nada porque el Status no cambia. Ver [00-patrones-base §5](00-patrones-base.md#5-los-mismos-patrones-en-los-otros-triggers). |
| **Async (Módulo 4): Scheduled + Batch** | `Schedulable` que solo delega ([ActiveSubscriptionRecountScheduler.cls:22-24](../../force-app/main/default/classes/ActiveSubscriptionRecountScheduler.cls#L22-L24)); `Database.Batchable` con `start`/`execute`/`finish`, sin `Database.Stateful` ([ActiveSubscriptionRecountBatch.cls:17](../../force-app/main/default/classes/ActiveSubscriptionRecountBatch.cls#L17)). |
| **Sin fallar en silencio** | `Database.update( lista, false )` + Error Log ([ActiveSubscriptionCounter.cls:146-147](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L146-L147)). |

---

## 6. Tests

Todos usan `@testSetup`, `Test.startTest()/stopTest()`, la `TestDataFactory` (`createProduct`, `createContract`, `buildSubscriptions`) y asserts con mensaje. Notas clave:

- **`buildSubscriptions`** crea Subscriptions **sin fechas propias**, como las de CPQ en el org: toman las del Contract por las fórmulas. Acepta cantidad negativa para simular una baja de Amendment.
- **Batch en test:** `stopTest()` fuerza a que corra; `execute()` corre una sola vez.
- **Scheduler en test:** usa `JOB_NAME + ' (Test)'` para no chocar con el job real del org (aprendizaje del 02/10/2026).

| Tipo | Caso | Archivo:método |
|---|---|---|
| **Positivo** | Subscription vigente → 1 | [ActiveSubscriptionCounterTest.cls:33](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L33) `activeSubscriptionCountsTest` |
| **Negativo** | Empieza mañana → 0 | [ActiveSubscriptionCounterTest.cls:46](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L46) `futureSubscriptionNotCountedTest` |
| **Borde** | Fin ayer no / fin hoy sí → 1 | [ActiveSubscriptionCounterTest.cls:62](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L62) `endDateBoundaryTest` |
| **Borde** | Terminada hoy no / mañana sí → 1 | [ActiveSubscriptionCounterTest.cls:79](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L79) `terminatedDateBoundaryTest` |
| **Positivo** | Contract evergreen (sin fin) → 1 | [ActiveSubscriptionCounterTest.cls:96](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L96) `evergreenContractTest` |
| **Positivo (Amendments)** | 125 + 100 − 10 → **1, no 3** | [ActiveSubscriptionCounterTest.cls:116](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L116) `amendmentRevisionsCountOnceTest` |
| **Negativo (Amendments)** | 125 − 125 → 0 | [ActiveSubscriptionCounterTest.cls:132](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L132) `fullCancellationNotCountedTest` |
| **Borde (Amendments)** | Baja total desde mañana → hoy sigue en 1 | [ActiveSubscriptionCounterTest.cls:147](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L147) `futureCancellationStillCountsTest` |
| **Negativo (límites)** | Set vacío → 0 queries | [ActiveSubscriptionCounterTest.cls:166](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L166) `emptySetSkipsQueryTest` |
| **Negativo (límites)** | Número ya correcto → 0 DML | [ActiveSubscriptionCounterTest.cls:179](../../force-app/main/default/classes/ActiveSubscriptionCounterTest.cls#L179) `unchangedCountSkipsUpdateTest` |
| **Positivo (insert)** | 2 en A + 1 en B en un insert → 2 / 1 | [SubscriptionTriggerHandlerTest.cls:26](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L26) `insertTest` |
| **Positivo (update)** | TerminatedDate = hoy → 0 | [SubscriptionTriggerHandlerTest.cls:42](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L42) `updateRelevantFieldTest` |
| **Negativo (update)** | Cambia el precio → **no** recalcula (sigue en 99 forzado) | [SubscriptionTriggerHandlerTest.cls:60](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L60) `updateIrrelevantFieldTest` |
| **Positivo (update)** | Se mueve de A a B → A = 0, B = 1 | [SubscriptionTriggerHandlerTest.cls:78](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L78) `moveToAnotherContractTest` |
| **Positivo (delete)** | Borra 1 de 2 → 1 (`Trigger.old`) | [SubscriptionTriggerHandlerTest.cls:94](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L94) `deleteTest` |
| **Positivo (undelete)** | Recupera → 1 | [SubscriptionTriggerHandlerTest.cls:109](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L109) `undeleteTest` |
| **Negativo** | Sin Contract → sin errores ni logs | [SubscriptionTriggerHandlerTest.cls:125](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L125) `subscriptionWithoutContractTest` |
| **Bulk 200 (insert)** | 200 en un Contract → 200 | [SubscriptionTriggerHandlerTest.cls:139](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L139) `bulkInsertTest` |
| **Bulk 200 (delete)** | Borra las 200 → 0 | [SubscriptionTriggerHandlerTest.cls:154](../../force-app/main/default/classes/SubscriptionTriggerHandlerTest.cls#L154) `bulkDeleteTest` |
| **Positivo (Batch)** | Vence por tiempo: antes del Batch sigue en 1 (el trigger no se entera), después 0 | [ActiveSubscriptionRecountBatchTest.cls:27](../../force-app/main/default/classes/ActiveSubscriptionRecountBatchTest.cls#L27) `expiredByTimeTest` |
| **Positivo (Batch)** | Número incorrecto (7) → 1 (backfill) | [ActiveSubscriptionRecountBatchTest.cls:52](../../force-app/main/default/classes/ActiveSubscriptionRecountBatchTest.cls#L52) `fixWrongCountTest` |
| **Bulk 200 (Batch)** | 200 Contracts en 5 sin Subscriptions → 0 | [ActiveSubscriptionRecountBatchTest.cls:69](../../force-app/main/default/classes/ActiveSubscriptionRecountBatchTest.cls#L69) `bulkRecountTest` |
| **Positivo (Scheduler)** | Cron `0 0 2 * * ?` + 1 Batch lanzado | [ActiveSubscriptionRecountSchedulerTest.cls:14](../../force-app/main/default/classes/ActiveSubscriptionRecountSchedulerTest.cls#L14) `scheduleNightlyJobTest` |

23 tests, cobertura **100%** en las 5 piezas. Build Tracker: [DEV4.md §9](../code-review/DEV4.md#9-tests-cobertura-y-build-tracker).

---

## 7. Edge cases cubiertos y supuestos

**Edge cases** (tabla completa con su test en [DEV4.md §6](../code-review/DEV4.md#6-edge-cases)):

- Bordes de fecha: empieza mañana no cuenta; vence hoy sí cuenta; terminada hoy no cuenta; evergreen (sin fin) cuenta.
- Amendments: +100 / −10 → 1, no 3; baja total a 0 → deja de contar; baja total con fecha futura → hoy sigue contando; revisiones con cantidad 0 (Percent Of Total, caso real del 00000112) → no suman ni restan.
- Update de un campo irrelevante → 0 queries. Se mueve de Contract → se recalculan los dos.
- Delete / undelete → baja y vuelve. Subscription sin Contract → se ignora.
- Set vacío → 0 queries; número igual → 0 DML.
- 200 inserts / 200 deletes / 200 Contracts en el Batch → dentro de los límites.
- Vence o empieza por tiempo → lo corrige el Batch esa noche.
- Falla el update de un Contract → `Error_Log__c`, el resto se guarda y el contracting de CPQ sigue.

**Supuestos** (detalle en [DEV4.md §5](../code-review/DEV4.md#5-supuestos-y-decisiones)):

- **"Activa" = vigente hoy:** inicio vacío o ≤ hoy, fin vacío o ≥ hoy, TerminatedDate vacío o **>** hoy. Se leen las fórmulas `SBQQ__StartDate__c` / `SBQQ__EndDate__c` (fecha propia o la del Contract).
- **No se mira el estado del Contract** (Draft/Activated): el requirement habla de Subscriptions activas, y activar el Contract es del DEV #3.
- **Amendments, opción C:** una por Subscription original con cantidad neta vigente > 0.
- **"Hoy"** = `Date.today()` del usuario que dispara (o del que programó el job, America/Los_Angeles). El número puede estar atrasado **hasta las 2:00** cuando el cambio es solo por fecha.
- Sharing Public Read/Write en Contract y Subscription (`with sharing` ve todo).

---

## 8. Cinco preguntas probables del revisor

**1. ¿Por qué no usaste un Roll-Up Summary?**
Porque solo existen en Master-Detail y `SBQQ__Contract__c` es un **Lookup** del paquete de CPQ que no podemos cambiar. Además un Roll-Up no puede filtrar por `TODAY()`, y "activa" depende de la fecha; tampoco sabría agrupar los Amendments por su original. Por eso es Apex.

**2. ¿Por qué los cuatro contextos son after, y por qué en delete usás `Trigger.old`?**
After porque cambio otro registro (el Contract) con DML y la query tiene que ver el dato ya guardado: en before insert la Subscription no tiene Id, y en before delete la query todavía la contaría. En delete `Trigger.new` no existe: los registros borrados, con su Contract, solo están en `Trigger.old`.

**3. Este Contract tiene 12 Subscriptions y el campo dice 8. ¿No está mal?**
No. CPQ no modifica la original en un Amendment: crea un registro por la diferencia (+100, −10) que apunta a ella. Para el vendedor sigue siendo **una** suscripción con otra cantidad. Sumo las cantidades por original y cuento las que tienen neto > 0. Además, hoy esas revisiones ni empezaron. Lo prueba `amendmentRevisionsCountOnceTest`.

**4. ¿Para qué el Batch si ya tenés el trigger?**
Porque una Subscription puede vencer o empezar sin que nadie la edite: el trigger solo corre cuando alguien guarda. A las 2:00 el Batch recuenta todos los Contracts con **el mismo** método (`ActiveSubscriptionCounter`), así la regla está en un solo lugar. Lo prueba `expiredByTimeTest`.

**5. ¿Está bulkificado? ¿Qué pasa si falla?**
Sí: `Set<Id>` de Contracts, 1 SOQL con subquery y como máximo 1 DML, sean 1 o 200 Subscriptions (`bulkInsertTest`, `bulkDeleteTest`). Recuento desde cero, así nunca se desfasa, y solo actualizo si cambió. Uso `Database.update( lista, false )`: si un Contract falla va a `Error_Log__c` y no se cae el contracting de CPQ; el Batch lo corrige esa noche.

Más preguntas (13 en total): [DEV4.md §7](../code-review/DEV4.md#7-preguntas-probables-del-code-review).
