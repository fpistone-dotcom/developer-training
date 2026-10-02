# DEV #1 — Vencimiento automático de la Quote · Resumen para el Code Review

> **Estado:** Parte A y Parte B terminadas, deployadas y probadas en el org (30/09/2026). Job nocturno programado y ya ejecutado sin errores (01/10/2026).

---

## 1. Qué pide el requirement

> "Whenever a Quote record is approved, the Quote Expiration Date should be set to 30 days from the date in which it was approved. If a Quote reaches the Quote Expiration Date and the related Opportunity is still not 'Closed Won,' then the Quote approvals should be recalled."

**En 2 líneas:** **(Parte A)** cuando una Quote se aprueba, su vencimiento pasa a ser 30 días desde la aprobación. **(Parte B)** si una Quote vence esperando aprobación y la venta no se ganó, se retira (recall) esa aprobación pendiente.

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "whenever a Quote record is approved" | `SBQQ__Status__c` **pasa a** `Approved` (o la Quote nace aprobada) | `QuoteTriggerHandler.beforeUpdate` / `beforeInsert` |
| (B) "30 days from the date in which it was approved" | `SBQQ__ExpirationDate__c = hoy + 30`, pisando el default de CPQ | `QuoteTriggerHandler.setExpirationDate` |
| (C) "reaches the Quote Expiration Date" | `SBQQ__ExpirationDate__c <= TODAY`, chequeado todas las noches | `QuoteExpirationBatch.start` + `QuoteExpirationScheduler` |
| (D) "the related Opportunity is still not 'Closed Won'" | Con Opportunity y `IsWon = false` | `QuoteExpirationBatch.start` |
| (E) "the Quote approvals should be recalled" | Retirar la aprobación **pendiente** (botón "Recall" = acción `'Removed'`) | `QuoteExpirationBatch.recallPendingApprovals` |

---

## 2. Diseño elegido

### Piezas

| Componente | Tipo | Parte | Rol |
|---|---|---|---|
| `QuoteTrigger` | Apex Trigger | A | Único trigger propio de `SBQQ__Quote__c`, sin lógica. `before insert` y `before update`. |
| `QuoteTriggerHandler` | Apex Class | A | Métodos de entrada por contexto + lógica `private static`. |
| `QuoteExpirationScheduler` | Apex Class (Schedulable) | B | "Despertador" nocturno: solo lanza el Batch. |
| `QuoteExpirationBatch` | Apex Class (Batchable) | B | Busca las Quotes vencidas con aprobación pendiente y les hace recall. |
| `ErrorLogUtil` / `Error_Log__c` | Reutilizados del DEV #2 | B | Registro de errores del recall. |
| `TestDataFactory` (`buildQuotes`, `createOpportunity`) | Test utility | A y B | Datos de prueba compartidos. |
| `QuoteTriggerHandlerTest` | Test Class | A | 8 tests. |
| `QuoteExpirationBatchTest` | Test Class | B | 8 tests, con aprobaciones pendientes reales. |
| `QuoteExpirationSchedulerTest` | Test Class | B | 1 test. |

En el org también existen `SBQQ.QuoteBefore` y `SBQQ.QuoteAfter`, del paquete CPQ. No son nuestros y no se pueden modificar.

### Cómo se aprueba una Quote en el org (contexto)

Los 2 Approval Processes activos (`Auto_Approval` y `Quote_Approval_V2`, con criterios de entrada opuestos) tienen las mismas acciones:

| Momento | Field update | Status |
|---|---|---|
| Submit | `Set_Quote_Status_In_Review` | In Review (y bloquea) |
| Aprobación final | `Set_Quote_Status_Approved` (+ template Final) | **Approved** (bloqueada) |
| Rechazo | `Set_Quote_Status_Denied` | Denied (desbloquea) |
| Recall (solo pendientes) | `Set_Quote_Status_Draft` | Draft (desbloquea) |

**Consecuencia para el diseño:** "aprobada" = el campo `SBQQ__Status__c` pasa a `Approved`. Un field update **dispara los triggers de update**, así que el trigger ve la aprobación igual que si la hiciera un usuario.

### Por qué así y qué descartamos

**Parte A**

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| **Trigger `before update`** | Cambiamos un campo **del mismo registro**: se asigna en memoria y Salesforce lo guarda solo. 0 DML, sin recursión. | **After update + DML:** otro `update`, recursión, y choca con el **bloqueo** de la aprobación. |
| **Detectar el cambio del campo, no el proceso** | Funciona por cualquier vía: Approval Process, edición manual o integración. | **Field update `TODAY()+30` en el Approval Process:** solo cubre esa vía, y además es IC, no DEV. |
| **También `before insert`** | Quotes que **nacen** aprobadas (cargas de datos, tests). Cuesta 0 queries. | Ignorarlas: se quedarían con el vencimiento de CPQ. |

**Parte B**

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| **Scheduler + Batch, no trigger** | "La Quote venció" **no es un guardado**: es el calendario que avanza. Un trigger nunca se enteraría. | Trigger: imposible. **Solo Scheduled:** una transacción con un solo juego de límites. |
| **Batch** | Tandas de 200, **cada una con sus propios governor limits**: escala con cualquier volumen. | — |
| **Recall = acción `'Removed'`** | Es exactamente el botón "Recall". Salesforce corre la Recall Action (Draft) y **desbloquea solo**. | **`Approval.unlock` + cambiar el status:** necesita *Enable record locking and unlocking in Apex*, que está desactivado. |
| **Solo Quotes In Review** | Decisión del mentor: el recall aplica a aprobaciones **pendientes**. Una aprobación terminada no tiene nada que retirar. | Tocar las aprobadas: el "recall" de algo terminado no existe en Salesforce. |

---

## 3. Flujo paso a paso

### Día 1: el vendedor crea la Quote y la manda a aprobación

1. **El vendedor crea la Quote.** CPQ pone el vencimiento por defecto (creación + 30).
   → `QuoteTrigger` (before insert) → `QuoteTriggerHandler.beforeInsert` → `setExpirationDateOnInsert`. Nace en Draft, así que **no hace nada**.
2. **El vendedor hace Submit.** El Approval Process (field update) la pasa a **In Review**, la **bloquea** y crea un **work item** (la tarea en "Items to Approve").
   → `QuoteTrigger` (before update) → `beforeUpdate` → `setExpirationDateOnUpdate`. Pasó a In Review, no a Approved, así que **no hace nada**. La Quote sigue con el vencimiento de CPQ.

### Camino 1: la aprueban (Parte A)

3. **El aprobador hace clic en Approve.** El field update `Set_Quote_Status_Approved` la pasa a **Approved**.
4. → `QuoteTrigger` (before update) → `QuoteTriggerHandler.beforeUpdate` → **`setExpirationDateOnUpdate`**: compara con `Trigger.oldMap`. Antes era In Review y ahora es Approved, así que **cambió a Approved** y entra en la lista.
5. → **`setExpirationDate`**: calcula `Date.today().addDays( 30 )` una vez y lo asigna en memoria. Salesforce lo guarda en el mismo save (0 SOQL, 0 DML).
6. **Resultado:** Approved, bloqueada, con vencimiento **hoy + 30**. Esa noche el Batch busca `In Review`, así que **nunca la trae**.

### Camino 2: nadie la aprueba y vence (Parte B)

3. **Pasan los días.** Cada noche el Batch corre, pero mientras no venza no la trae.
4. **La noche del vencimiento, a la 1:00**, Salesforce dispara el job → **`QuoteExpirationScheduler.execute`** → `Database.executeBatch( new QuoteExpirationBatch() )`.
5. → **`QuoteExpirationBatch.start`**: **una** query trae las Quotes `In Review`, vencidas (`<= TODAY`), con Opportunity y `IsWon = false`.
6. Salesforce parte el resultado en paquetes de 200 y llama a **`execute`** por cada uno → **`recallPendingApprovals`**:
   - a. Junta los Ids en un `Set<Id>`.
   - b. **Una** query a `ProcessInstanceWorkitem` trae las aprobaciones pendientes de esas Quotes.
   - c. Por cada work item arma un `Approval.ProcessWorkitemRequest` con la acción `'Removed'` y un comentario.
   - d. Si no hay ninguno, `return`.
   - e. **Un** `Approval.process( lista, false )` hace todos los recalls juntos.
7. **Salesforce, por cada recall:** corre la Recall Action (`Set_Quote_Status_Draft`), así que la Quote queda en **Draft**.
   → `QuoteTrigger` → `setExpirationDateOnUpdate`: pasó a Draft, no a Approved, así que **no hace nada** (sin recursión).
   La Quote se **desbloquea** y el Approval History muestra **Recalled** con el comentario.
8. → `recallPendingApprovals` recorre los resultados por posición. Si alguno falló → `ErrorLogUtil.buildLog` + `ErrorLogUtil.saveLogs`.
9. → **`finish`**: no hace nada. El job vuelve a dormir hasta la noche siguiente.
10. **Al día siguiente** el vendedor corrige la Quote (está en Draft y editable) y la vuelve a mandar. El ciclo arranca de nuevo.

### Camino 3: ganan la venta antes

La Opportunity pasa a Closed Won, así que `IsWon = true` y el Batch la excluye en `start`.

---

## 4. Código explicado por bloques

### `QuoteTrigger`

```apex
trigger QuoteTrigger on SBQQ__Quote__c ( before insert, before update ) {
    if ( Trigger.isBefore && Trigger.isInsert ) {
        QuoteTriggerHandler.beforeInsert( Trigger.new );
    } else if ( Trigger.isBefore && Trigger.isUpdate ) {
        QuoteTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    }
}
```
- **Qué hace:** mira el contexto y delega en el handler. En insert no hay `oldMap`, porque no existe versión anterior.
- **Regla del training:** un trigger por objeto, sin lógica, con variables de contexto (**Módulo 2**).

### `QuoteTriggerHandler`

**Bloque 1: constantes**
```apex
public static final String STATUS_APPROVED = 'Approved';
public static final Integer DAYS_UNTIL_EXPIRATION = 30;
```
- **Qué hace:** define el valor buscado y los días de vigencia.
- **Por qué así:** `static final` en UPPER_CASE (**Módulo 1**). Son `public` para que los tests usen el mismo valor (DRY).

**Bloque 2: entradas `beforeInsert` / `beforeUpdate`**
- **Qué hace:** cada una solo delega.
- **Regla del training:** patrón de handler, métodos de entrada que llaman a `private static` (**Módulo 2**).

**Bloque 3: `setExpirationDateOnInsert`**
```apex
if ( newQuote.SBQQ__Status__c == STATUS_APPROVED ) { approvedQuoteList.add( newQuote ); }
```
- **Qué hace:** junta las Quotes que nacen aprobadas.
- **Por qué así:** for mejorado sobre toda la lista (bulkificado) e `if` con llaves (**Módulo 1**).

**Bloque 4: `setExpirationDateOnUpdate`**
```apex
SBQQ__Quote__c oldQuote = oldQuoteByIdMap.get( newQuote.Id );
Boolean statusChanged = newQuote.SBQQ__Status__c != oldQuote.SBQQ__Status__c;
if ( statusChanged && newQuote.SBQQ__Status__c == STATUS_APPROVED ) { ... }
```
- **Qué hace:** solo procesa las Quotes cuyo status **cambió** a Approved.
- **Regla del training:** usar `Trigger.oldMap` para correr la lógica solo si el campo cambió (**Governor Limits**). Sin esto, cada edición alargaría el vencimiento.

**Bloque 5: `setExpirationDate`**
```apex
if ( approvedQuoteList.isEmpty() ) { return; }
Date expirationDate = Date.today().addDays( DAYS_UNTIL_EXPIRATION );
for ( SBQQ__Quote__c approvedQuote : approvedQuoteList ) {
    approvedQuote.SBQQ__ExpirationDate__c = expirationDate;
}
```
- **Qué hace:** calcula la fecha una vez (afuera del loop) y la asigna a todas.
- **Por qué así:** una sola regla para insert y update (DRY). Sin DML, porque estamos en before (**Módulo 2**). El tipo es `Date` porque el campo es Date (**Módulo 1**).

### `QuoteExpirationScheduler`

```apex
public static final String JOB_NAME = 'Quote Expiration Recall - Nightly';
public static final String CRON_EXPRESSION = '0 0 1 * * ?';

public void execute( SchedulableContext sc ) {
    Database.executeBatch( new QuoteExpirationBatch() );
}
```
- **Qué hace:** a la hora del cron (todos los días a la 1:00) lanza el Batch.
- **Regla del training:** implementa `Schedulable` y delega la lógica en otra clase (**Módulo 4**). Las constantes las usan el test y el script que lo programa (DRY).

### `QuoteExpirationBatch`

**Bloque 1: constantes**
- **Qué hace:** define `STATUS_IN_REVIEW`, `RECALL_ACTION = 'Removed'`, el comentario del recall y `CLASS_NAME` para los logs.
- **Por qué así:** no hay valores escritos a mano en la lógica (**Módulo 1**).

**Bloque 2: `start`**
```apex
SELECT Id FROM SBQQ__Quote__c
WHERE SBQQ__Status__c = :STATUS_IN_REVIEW
AND SBQQ__ExpirationDate__c <= TODAY
AND SBQQ__Opportunity2__c != null
AND SBQQ__Opportunity2__r.IsWon = false
```
- **Qué hace:** elige las Quotes a procesar y devuelve un `QueryLocator`.
- **Regla del training:** WHERE para traer solo lo necesario, campo del padre por la relación lookup (`__r`) y una cláusula por línea (**Módulo 1, SOQL**).

**Bloque 3: `execute`**
- **Qué hace:** se ejecuta una vez por paquete de 200 y solo delega en `recallPendingApprovals`.
- **Regla del training:** Batch para gran volumen. En tests, `execute()` corre una sola vez (**Módulo 4**).

**Bloque 4: `recallPendingApprovals`**
- **Qué hace, en cinco pasos:**
  1. Junta los Ids.
  2. Hace **una** query a `ProcessInstanceWorkitem` (las aprobaciones pendientes).
  3. Arma un request `'Removed'` por cada una y anota, en una **lista paralela**, a qué Quote corresponde cada request.
  4. Hace **un** `Approval.process( lista, false )`.
  5. Recorre los resultados **por posición** y guarda los errores con un solo insert.
- **Regla del training:** nada de SOQL ni DML en loops (**Governor Limits**). Sin fallar en silencio (**Módulo 3**). El `false` hace que un error no cancele los demás recalls.
- **`ProcessInstanceWorkitem`:** es el objeto estándar de Salesforce para las aprobaciones **pendientes**. Existe solo para Approval Processes, así que no hace falta filtrar por tipo.

**Bloque 5: `finish`**
- **Qué hace:** nada. La interfaz lo exige.

### `TestDataFactory` (lo agregado para el DEV #1)
- **`buildQuotes( accountId, n, status, expirationDate )`:** arma Quotes sin insertarlas. Recibe el vencimiento para poder **distinguirlo** del que calcula el trigger.
- **`createOpportunity( accountId, stageName )`:** crea una Opportunity abierta o ganada.

---

## 5. Supuestos y decisiones

- **"Recall" (definido con el mentor):** aplica solo a aprobaciones **pendientes** (acción `'Removed'`). Las Quotes ya aprobadas **no se tocan**. No hace falta `Approval.unlock` ni el setting de locking en Apex (desactivado en el org).
- **"Hoy" = el día de la aprobación:** el trigger corre en la misma transacción que aprueba. `Date.today()` usa la zona horaria del usuario.
- **Si el usuario cambia el vencimiento en el mismo guardado en que aprueba,** gana el nuestro.
- **Re-aprobación:** si la Quote vuelve a Draft o queda Denied y se aprueba de nuevo, el vencimiento se recalcula desde la nueva aprobación.
- **"Reaches the Expiration Date" = `<= TODAY`:** el recall se hace el mismo día del vencimiento (a la 1:00).
- **Quotes sin Opportunity:** quedan afuera del recall.
- **El job corre como el usuario que lo programó** (admin). Hacer recall de aprobaciones enviadas por otros requiere ser admin o quien la envió.
- **`with sharing`** en todas las clases. Como el job corre como admin, ve todas las Quotes.
- **Genérico `<SObject>`** en `Database.Batchable<SObject>`: lo exige la interfaz, no es una elección de diseño.
- **Sin `Database.Stateful`:** los errores se guardan en cada paquete, así que no hace falta guardar estado entre paquetes.
- **IC relacionado (consultado y autorizado):** se cerró el gap de las Quotes sin motivo de aprobación (`Auto_Approval`), y se unificaron Finance → Manager → Director en `Quote_Approval_V2` para el caso combinado. Ver CLAUDE.md, secciones 4 y 5.

---

## 6. Edge cases

**Parte A.** Todas las Quotes de test nacen con vencimiento **hoy + 5**. El default de CPQ (creación + 30) coincide con hoy + 30, y un test que solo mirara la fecha pasaría aunque el trigger no hiciera nada.

| Caso | Cómo se maneja | Test |
|---|---|---|
| Draft → Approved | Vencimiento hoy + 30 | `setExpirationOnApproveTest` |
| 200 Quotes → Approved juntas | Las 200 con hoy + 30 | `setExpirationOnApproveBulkTest` |
| Draft → In Review | Sin cambios | `notSetOnOtherStatusTest` |
| Ya aprobada, se edita otro campo | No se recalcula | `notRecalculatedWhenAlreadyApprovedTest` |
| Approved → Draft → Approved | Se recalcula | `recalculatedOnReapprovalTest` |
| Se crea ya aprobada | hoy + 30 | `setExpirationOnInsertApprovedTest` |
| 200 creadas aprobadas | Las 200 con hoy + 30 | `setExpirationOnInsertApprovedBulkTest` |
| Se crea en Draft | Sin cambios | `notSetOnInsertNotApprovedTest` |

**Parte B.** Las aprobaciones pendientes de los tests son **reales**: se hace Submit y `Quote_Approval_V2` corre en el test (Net 60 → pendiente de Finance).

| Caso | Cómo se maneja | Test |
|---|---|---|
| Vencida ayer + Opportunity abierta | Draft, sin work item, sin Error Logs | `recallExpiredQuoteTest` |
| Vence **hoy** (borde) | Draft | `recallQuoteExpiringTodayTest` |
| 200 vencidas | Las 200 en Draft | `recallBulkTest` |
| Vence mañana | In Review, sigue pendiente | `notRecalledWhenNotExpiredTest` |
| Opportunity Closed Won | In Review | `notRecalledWhenOpportunityWonTest` |
| Ya Approved y vencida | Approved (no se toca) | `notRecalledWhenAlreadyApprovedTest` |
| Sin Opportunity | In Review | `notRecalledWithoutOpportunityTest` |
| "In Review" a mano, sin aprobación pendiente | In Review, sin error | `notRecalledWithoutPendingApprovalTest` |
| El Scheduler se programa y lanza el Batch | `CronTrigger` con el cron + 1 `AsyncApexJob` | `scheduleNightlyJobTest` |
| El job real ya está programado en el org con el mismo nombre | El test programa el suyo con otro nombre (`JOB_NAME + ' (Test)'`) | `scheduleNightlyJobTest` |

---

## 7. Preguntas probables del Code Review

**1. ¿Por qué before update y no after update?**
Porque cambiamos un campo de la misma Quote que se está guardando. En before alcanza con asignarlo y Salesforce lo guarda junto con todo lo demás. En after el registro ya es de solo lectura: tendríamos que hacer otro `update`, que dispara el trigger de nuevo y choca con el bloqueo que pone la aprobación.

**2. ¿Por qué no hay SOQL ni DML en el handler? ¿Cómo se guarda la fecha?**
Todo lo que necesitamos viene en `Trigger.new` y `Trigger.oldMap`. Y en before, lo que asignamos a los registros de `Trigger.new` se guarda solo, en el mismo save que disparó el trigger. Cuesta 0 queries y 0 DML, sean 1 o 200 Quotes.

**3. ¿Cómo sabe el trigger que la Quote "pasó" a Approved y no que ya estaba aprobada?**
Compara el valor nuevo con el viejo (`Trigger.oldMap`, buscado por Id). Solo actúa si son distintos **y** el nuevo es Approved. Si la Quote ya estaba aprobada y se edita otra cosa, son iguales y se ignora. Lo prueba `notRecalculatedWhenAlreadyApprovedTest`.

**4. Si Approved lo pone un Approval Process, ¿por qué se dispara el trigger?**
Porque la acción del Approval Process es un **field update**, que por dentro es un update del registro, y todo update dispara los triggers. Para el trigger es lo mismo que un usuario editando. Por eso detectamos el cambio del campo y no nos importa quién lo hizo.

**5. ¿Por qué las Quotes de test nacen con vencimiento hoy + 5?**
Porque el default de CPQ es creación + 30, y en un test la Quote se crea hoy: daría hoy + 30, igual que nuestro trigger. El test pasaría aunque el trigger no hiciera nada (falso positivo). Con hoy + 5 se ve claro si la fecha la pisamos nosotros o no.

**6. ¿Cómo se cumple "30 días desde que se aprobó" si la aprobación tarda días?**
El trigger no corre en el Submit (eso solo pone In Review), corre cuando el status **pasa a Approved**, en el momento en que el aprobador aprueba. Si el Submit fue el lunes y se aprueba el jueves, vence 30 días después del jueves.

**7. ¿Por qué un Batch + Scheduler y no un trigger para el vencimiento?**
Un trigger solo corre cuando alguien guarda un registro, y "la Quote venció" no es un guardado: es el calendario que avanza. Hace falta algo que corra por tiempo: el Scheduler despierta todas las noches y el Batch procesa las Quotes en paquetes de 200, cada uno con sus propios límites.

**8. ¿Por qué recall = acción 'Removed'?**
En Apex, las acciones sobre una aprobación pendiente se hacen con `ProcessWorkitemRequest`: Approve, Reject o Removed. `'Removed'` es exactamente el botón "Recall" de la UI. Salesforce corre la Recall Action del proceso (Draft) y desbloquea la Quote solo, sin necesitar `Approval.unlock`.

**9. ¿Por qué no se hace recall de las Quotes ya aprobadas?**
Porque en Salesforce el recall existe solo para aprobaciones **pendientes**: una aprobación terminada no tiene nada que retirar. Lo definimos con el mentor. Hacer algo con las aprobadas hubiera requerido desbloquearlas por Apex, y ese setting está desactivado en el org.

**10. Si la Parte B no toca las aprobadas, ¿para qué sirve el vencimiento de la Parte A?**
El vencimiento es la **validez de la oferta**: sale en el documento que recibe el cliente y le indica al vendedor hasta cuándo valen esos precios. La Parte A hace que esa validez se cuente desde que la oferta quedó realmente aprobada, no desde que se creó el borrador.

**11. ¿Qué pasa si un recall falla?**
Usamos `Approval.process( lista, false )`: los demás recalls se hacen igual. El error se busca por posición en la lista de resultados (un resultado fallido no trae el Id) y se guarda en `Error_Log__c` con un solo insert. Se ve en la tab Error Logs.

**12. ¿Hay recursión entre el Batch y el trigger?**
El recall pasa la Quote a Draft y eso dispara `QuoteTrigger`, pero el trigger solo reacciona cuando el status pasa **a Approved**. Draft no lo activa, así que no hay loop.

**13. ¿Por qué el test del Scheduler usa otro nombre de job?**
Porque los jobs programados son de todo el org y **no se aíslan en los tests** como los registros. Cuando programamos el job real, el test empezó a fallar con "already scheduled": Salesforce no permite dos jobs con el mismo nombre. Con un nombre propio de test se evita el choque, y el test sigue verificando el cron y que se lance el Batch.

**14. ¿Cómo sé que el job corre de verdad?**
En **Setup → Scheduled Jobs** ("Quote Expiration Recall - Nightly") y en **Apex Jobs**. El 01/10/2026 corrió solo a la 1:09 (hora del org) y terminó *Completed* sin errores. Procesó 0 Quotes porque ninguna estaba vencida.

---

## 8. Cómo se prueba en la demo

### Parte A: vencimiento al aprobar
1. Abrir una Quote en Draft (Net 30, sin descuento) y anotar su **Expiration Date** (la de CPQ).
2. **Submit for Approval**. Con `Auto_Approval` se aprueba sola; con `Quote_Approval_V2`, aprobarla desde el aprobador.
3. Refrescar. **Tiene que verse:** Status **Approved** y Expiration Date = **hoy + 30**.

### Parte B: recall de una Quote vencida
1. Crear una Quote en una Opportunity **abierta**, con **Payment Terms = Net 60**, y editar **Expiration Date = ayer**.
2. **Submit for Approval**. **Tiene que verse:** Status **In Review**, el candado y la aprobación en "Items to Approve" de Finance.
3. **Developer Console → Debug → Open Execute Anonymous Window** y ejecutar:
   ```apex
   Database.executeBatch( new QuoteExpirationBatch() );
   ```
   Es lo mismo que hace el job a la 1:00, sin esperar.
4. Esperar unos segundos (el job se ve en **Setup → Apex Jobs**) y refrescar la Quote. **Tiene que verse:**
   - Status **Draft**, sin candado.
   - En el **Approval History**, el paso **Recalled** con el comentario *"Recalled automatically: ..."*.
   - La aprobación ya no figura en "Items to Approve".
5. Mostrar el job en **Setup → Scheduled Jobs** ("Quote Expiration Recall - Nightly") y la tab **Error Logs** vacía.

### Evidencia real en el org

| Prueba | Fecha | Resultado |
|---|---|---|
| Parte A: **Q-00061** (Net 30, vencimiento forzado al 05/10) → Submit → `Auto_Approval` | 30/09/2026 | Approved, vencimiento **30/10/2026**. Re-consultada después: CPQ no la pisó. |
| Parte A con los procesos nuevos: **Q-00072 a Q-00078** (7 casos de aprobación) | 30/09/2026 | Todas Approved con vencimiento hoy + 30 |
| Parte B: **Q-00079** (Net 60, vencida el 29/09) → Submit → Batch a mano | 30/09/2026 | Job Completed, 0 errores → **Draft**, Approval History "Removed" con comentario |
| Job nocturno automático | 01/10/2026, 1:09 | Completed, 0 Quotes (ninguna vencida), 0 errores |

---

## 9. Build Tracker

**Todos los tests locales del org pasan: 30/30.** Son Order 11, ErrorLogUtil 2, Parte A 8 y Parte B 9. **Cobertura del org: 98%.**

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| QuoteTrigger | QuoteTriggerHandlerTest | 02/10/2026 | 100% |
| QuoteTriggerHandler | QuoteTriggerHandlerTest | 02/10/2026 | 100% |
| QuoteExpirationBatch | QuoteExpirationBatchTest | 02/10/2026 | 93% |
| QuoteExpirationScheduler | QuoteExpirationSchedulerTest | 02/10/2026 | 100% |

---

## 10. Limitaciones conocidas y pendientes de QA

1. **Rama de error del recall sin cubrir.** Las líneas 112-113 de `QuoteExpirationBatch`, que arman el Error Log cuando un recall **falla**, no están cubiertas: un recall real no se puede hacer fallar con datos normales de test. Cobertura de la clase: 93%.
2. **Orden de triggers con CPQ.** Salesforce no garantiza el orden entre nuestro `QuoteTrigger` y el `SBQQ.QuoteBefore` de CPQ. Verificamos que CPQ no pisa la fecha con Quotes **sin Quote Lines**. Falta verificarlo con una Quote **con productos** y aprobación manual → **QA-DEV1-01**.
3. **Hora del job.** Corre a la 1:00 en la zona horaria del usuario que lo programó (America/Los_Angeles). Salesforce puede demorarlo unos minutos según la carga (el 01/10 corrió a la 1:09).
4. **El job depende del usuario que lo programó.** Si ese usuario se desactiva, el job deja de correr. Hay que reprogramarlo con otro admin.
5. **Recall de una Quote vencida en un caso real** (sin forzar la fecha), observando el job nocturno → **QA-DEV1-02**.

Detalle de los casos de QA en [`docs/qa-pending.md`](../qa-pending.md).
