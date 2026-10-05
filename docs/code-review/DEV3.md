# DEV #3 — Renewal Opportunity y Renewal Quote automáticas · Resumen para el Code Review

> **Estado:** terminado, deployado y probado en el org (05/10/2026). Job nocturno programado a las 3:00. Contract de la demo (00000110) preparado en Draft. **Corrección del mismo día:** filtro para no mandar emails de la Renewal Quote temporal de CPQ (ver "Hallazgo" en la sección 2).

---

## 1. Qué pide el requirement

> "As a Sales User, I would like a Renewal Opportunity to automatically be generated when a Contract is activated so that I can accurately forecast future sales. In addition, 30 days before the end of a Contract, I would like the Renewal Opportunity to be updated and a Renewal Quote generated so that my team can start preparing for the renewal sale. When this happens, the Owner of the Quote should have an email notification sent to them indicating that a Renewal Quote has been created, and the email should include a link to the Quote."

**En 2 líneas:** **(Parte 1)** cuando se activa un Contract, se crea su Renewal Opportunity. **(Parte 2)** 30 días antes del fin se genera la Renewal Quote y se actualiza la Opportunity. **(Parte 3)** el Owner de esa Quote recibe un email con el link.

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "when a Contract is activated" | El `Status` **pasa** a `Activated` (comparando con `Trigger.oldMap`) | `ContractTriggerHandler.setRenewalForecastOnActivation` |
| (B) "a Renewal Opportunity ... generated" | Se tilda `SBQQ__RenewalForecast__c` y CPQ la crea en el mismo save | `ContractTriggerHandler` + CPQ (`SBQQ.ContractAfter`) |
| (C) "30 days before the end of a Contract" | Activated, `EndDate` entre hoy y hoy + 30, todavía sin Renewal Quote | `RenewalQuoteBatch.start` + `RenewalQuoteScheduler` (3:00) |
| (D) "a Renewal Quote generated" | Se tilda `SBQQ__RenewalQuoted__c` y CPQ la crea en el mismo save | `RenewalQuoteBatch.requestRenewalQuotes` + CPQ |
| (E) "the Renewal Opportunity to be updated" | De `Prospecting` a `Proposal/Price Quote` (CPQ además le pone la Quote como Primary y sincroniza productos y Amount) | `RenewalQuoteBatch.updateRenewalOpportunityStage` |
| (F) "a Renewal Quote has been created" | Nace una Quote con `SBQQ__Type__c = 'Renewal'` | `QuoteTriggerHandler.afterInsert` |
| (G) "the Owner of the Quote ... email ... link" | Email al `OwnerId` con `https://<org>/<Id de la Quote>` | `QuoteTriggerHandler.sendRenewalQuoteNotifications` |

---

## 2. Diseño elegido

### Piezas

| Componente | Tipo | Parte | Rol |
|---|---|---|---|
| `ContractTrigger` | Apex Trigger (nuevo) | 1 | Único trigger propio de Contract, sin lógica. Solo `before update`. |
| `ContractTriggerHandler` | Apex Class (nueva) | 1 | Tilda `SBQQ__RenewalForecast__c` cuando el Contract se activa. |
| `RenewalQuoteScheduler` | Apex Class (Schedulable, nueva) | 2 | "Despertador" a las 3:00: lanza el Batch con tandas de 1. Job: *Renewal Quote Generation - Nightly*. |
| `RenewalQuoteBatch` | Apex Class (Batchable, nueva) | 2 | Busca los Contracts en la ventana, tilda `SBQQ__RenewalQuoted__c` y pasa la Opportunity a Proposal/Price Quote. |
| `QuoteTrigger` | Apex Trigger (existente, DEV #1) | 3 | Se le sumó `after insert`. |
| `QuoteTriggerHandler` | Apex Class (existente, DEV #1) | 3 | Se le sumó `afterInsert` → `sendRenewalQuoteNotifications` + `buildEmailBody`. |
| `ErrorLogUtil` / `Error_Log__c` | Reutilizados del DEV #2 | 2 y 3 | Registro de errores (updates fallidos, email fallido). |
| `TestDataFactory` (`buildContracts`, `buildRenewalOpportunities`) | Test utility | 1 y 2 | Datos de prueba compartidos. `createContract` ahora reutiliza `buildContracts`. |
| 3 Test Classes nuevas + 3 tests nuevos en `QuoteTriggerHandlerTest` | Test | 1, 2 y 3 | 17 tests nuevos (ver sección 9). |
| `scripts/apex/dev3-1/2/3-*.apex` | Scripts | Demo | Arman un Contract con Amendments para probar y para la demo. |

En el org también existen `SBQQ.ContractBefore` / `SBQQ.ContractAfter` y `SBQQ.QuoteBefore` / `SBQQ.QuoteAfter` (del paquete CPQ). No son nuestros y conviven con los nuestros. **No se tocó nada del IC.**

### Lo que verificamos en el org antes de programar (Paso 0, Contract 00000107)

| Prueba | Resultado |
|---|---|
| Activar + tildar `SBQQ__RenewalForecast__c` en **el mismo save** | La Renewal Opportunity ya existía al terminar el save (**síncrona**): "Renewal Opportunity", **Prospecting**, CloseDate = fin del Contract, `SBQQ__Renewal__c = true`, `SBQQ__RenewedContract__c` = el Contract. 125 × 120 = 15.000 |
| Tildar `SBQQ__RenewalQuoted__c` | La Renewal Quote **Q-00085** nació en el mismo save (**síncrona**): `Type = Renewal`, Draft, **Primary**, **Owner = el de la Opportunity**, 1 línea |
| Lo asíncrono | En cada caso CPQ encola **1** `QueueableCalculatorService` (cálculo de precios) |
| La Opportunity después de la Quote | Sigue en **Prospecting**: CPQ no cambia la etapa |
| Settings de CPQ | Ningún Contract del org tenía los flags tildados: CPQ **no** los tilda solo |
| Insertar un Contract ya Activated (con rollback) | **No se puede:** `FAILED_ACTIVATION`. Por eso no hay before insert |

### Hallazgo después de la primera prueba: la Renewal Quote temporal de CPQ

Después del deploy, Francisco recibió **dos** emails: el de Q-00092 (real, el link funciona) y otro de **Q-00090**, cuyo link no funcionaba porque esa Quote estaba en la papelera. No la borró nadie a mano: **la borró CPQ.**

**Qué hace CPQ al tildar *Renewal Forecast* (activación):** crea una **Renewal Quote temporal** (Type Renewal, Primary, Draft, montos en 0, `Uncalculated = true`), encola su `QueueableCalculatorService` para calcular los precios de los productos de la Renewal Opportunity y, **cuando el cálculo termina, la borra**. Evidencia en el org:

| Quote temporal | Nació (activación) | Se borró | Fin del `QueueableCalculatorService` |
|---|---|---|---|
| Q-00083 (Paso 0, Contract 00000107) | 14:19:42 | 14:19:50 | 14:19:50 |
| Q-00090 (E2E, Contract 00000109) | 14:49:55 | 14:49:59 | 14:49:59 |
| Q-00106 (Fix Test, Contract 00000111) | 15:45:24 | 15:45:29 | — (mismo patrón) |

Además, el debug log mostró que CPQ inserta **otra** Renewal Quote en cada paso y la **deshace en la misma transacción** con un rollback interno (Q-00089, Q-00091, Q-00105, Q-00107: no existen ni en la papelera). Ese rollback también descarta el email que encoló nuestro trigger, por eso nunca llegaron. En el Paso 0 no lo vimos porque solo consultamos Quotes vivas.

**El problema:** en el `after insert` la temporal es **idéntica** a una real (Renewal, Primary, Draft, sin calcular). Por sus campos no se pueden distinguir.

**La solución (opción A, confirmada por Francisco):** mandar el email solo si el Contract que renueva la Quote tiene **`SBQQ__RenewalQuoted__c = true`**, o sea, si alguien **pidió** una Renewal Quote (el Batch o un usuario). La temporal nace en la activación, cuando ese flag está en false. Se lee en la misma query que ya existía, subiendo por los lookups Quote → Opportunity → Contract (`SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c`): 0 queries extra.

**Supuestos verificados antes de programar** (transacción de prueba sobre el 00000111, deshecha al final con un error a propósito, sin datos ni emails):
1. La Renewal Opportunity ya tiene `SBQQ__RenewedContract__c` cuando termina la activación. En el flujo real la Quote de verdad nace en una transacción posterior (la del Batch), así que la Opportunity ya lo tiene. ✅
2. La query ve `SBQQ__RenewalQuoted__c = false` justo después de activar y `true` justo después de tildarlo, **en la misma transacción**. ✅

| Descartada | Por qué |
|---|---|
| B. Mandar el email desde el Batch | Dejaría de avisar por las Renewal Quotes generadas a mano (cambiaba la decisión 5) |
| C. Email diferido con un Queueable que revise si la Quote sigue existiendo | Carrera de tiempos y más piezas. Desde el Batch ya usamos el único cupo de Queueable |

### Por qué así y qué descartamos

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| **Tildar los flags nativos de CPQ** | CPQ arma todo bien: una línea por producto con las cantidades combinadas (125 + 100 − 10 = **215**), precios, `SBQQ__RenewedContract__c`, Quote Primary, fechas, Pricebook. Es lo mismo que hace el botón nativo. Nuestro código queda chico. | **Crear Opportunity, Quote y líneas a mano:** reimplementar la lógica de renewal de CPQ (Amendments, precios, co-terminación). Mucho código, fácil de equivocar, y CPQ no recalcula bien líneas armadas a mano. |
| **Parte 1 en `before update`** | Tildar el flag es cambiar un campo **del mismo registro**: se asigna en memoria, 0 DML, sin recursión. En el mismo save, `SBQQ.ContractAfter` ve el flag nuevo y crea la Opportunity. | **After update:** un `update` extra del mismo Contract, que vuelve a disparar todos los triggers (va contra la regla del training). |
| **Sin before insert** | Salesforce no deja crear un Contract ya Activated (verificado). Sería código que nunca corre y que ningún test puede cubrir. | Dejarlo "por las dudas": código muerto. |
| **Parte 2 con Batch + Scheduler** | "Faltan 30 días" no es un guardado: es el calendario que avanza (igual que en el DEV #1 y el DEV #4). | Trigger: nunca se enteraría. |
| **Ventana "30 días o menos" + flag como marca** | Si el job falla una noche, o si un Contract se activa con menos de 30 días por delante, la noche siguiente lo procesa igual. `SBQQ__RenewalQuoted__c = true` evita procesarlo dos veces (idempotente). | `EndDate = hoy + 30` exacto: si esa noche falla, el Contract se pierde para siempre. |
| **Tandas de 1 Contract** | Confirmado en el org: CPQ encola **un** Queueable por cada Renewal Quote, y desde un `execute` de Batch solo se puede encolar **1**. Además, los tests mostraron que la generación de CPQ con muchos Contracts juntos rompe el límite de queries **dentro de su código**. Son pocos Contracts por noche. | Tandas de 200: "Too many queueable jobs" y "SBQQ: Too many SOQL queries". |
| **Etapa en el Batch, solo desde Prospecting** | Es el evento exacto del requirement ("30 days before ... updated"). Corre en nuestra transacción, después de que CPQ creó la Quote. Si un vendedor ya movió la Opportunity, no la pisamos. | **En el after insert de la Quote:** correría dentro del insert de CPQ, antes de que existan las líneas, y mezclaría el email con cambios de datos. **"Si no está cerrada":** podría hacer retroceder una Opportunity en Negotiation/Review. |
| **Email en el after insert del `QuoteTrigger`** | Avisa por cualquier Renewal Quote **pedida** (Contract con `SBQQ__RenewalQuoted__c = true`), la genere el Batch o un usuario. En after porque el link necesita el Id. El filtro descarta la Quote temporal de CPQ (ver "Hallazgo"). | **Desde el Batch:** solo cubre ese camino y habría que buscar la Quote. |
| **Email armado en Apex (sin Email Template)** | No suma metadata (IC). Con un User como destinatario, Salesforce no deja usar `whatId`, así que los merge fields de la Quote no funcionan en un template. | Email Template: metadata nueva y merge fields limitados. |
| **`setTargetObjectId( OwnerId )`** | Los emails a usuarios internos **no cuentan** para el límite diario del org (15 en Developer Edition). | `setToAddresses( email )`: cuenta para el límite diario. |
| **try/catch alrededor del envío** | El email se manda dentro del save en el que CPQ crea la Quote. Una excepción sin atrapar haría rollback de la Renewal Quote. El error queda en `Error_Log__c`. | Sin try/catch: un problema de email rompería la renovación. |
| **Job a las 3:00** | Después de los jobs del DEV #1 (1:00) y del DEV #4 (2:00). | **A la misma hora que otro job:** competirían por la cola async y podrían tocar los mismos registros a la vez (el DEV #4 y el DEV #3 escriben en el Contract). **De día:** cambios mientras los usuarios trabajan. |

### Decisiones chicas del código: por qué sí y por qué no las otras

*(Agregado el 05/10/2026, regla nueva del CLAUDE.md.)*

| Decisión | Por qué sí | Otras opciones y qué pasaría |
|---|---|---|
| **`STATUS_ACTIVATED` como constante, definida UNA sola vez** | El texto `'Activated'` tiene nombre y vive en un solo lugar: `ContractTriggerHandler.STATUS_ACTIVATED` (pública). `RenewalQuoteBatch` la reutiliza en su query (`:ContractTriggerHandler.STATUS_ACTIVATED`), igual que el Queueable del DEV #2 usa `OrderTriggerHandler.STATUS_DRAFT` / `STATUS_ACTIVATED`. Al principio el Batch tenía su propia copia; se unificó en el congelamiento del código (05/10/2026). | **Escribir `'Activated'` suelto en cada lugar:** un error de tipeo (`'Activate'`) compila igual y la query no trae nada, sin error. **Una copia por clase (como estaba antes):** funciona, pero son dos fuentes de verdad: si alguien cambia una y no la otra, el trigger y el Batch dejan de coincidir (no es DRY). **Una clase aparte de constantes (`Constants`):** más "senior", pero agrega una clase solo para un String; el handler del objeto ya es el dueño natural del valor. |
| **`!newContract.SBQQ__RenewalForecast__c` antes de tildarlo** | No pisamos un flag que ya está tildado (por ejemplo, si alguien lo tildó a mano). | **Tildarlo siempre:** da el mismo resultado, pero sería una asignación innecesaria y menos clara. |
| **`Database.update( lista, false )` en el Batch** | Si un Contract falla, se registra y la noche siguiente se reintenta (el flag queda en false). | **`update lista`:** un error haría fallar toda la tanda sin Error Log. Con tanda de 1 da casi lo mismo, pero el test bulk usa 200. |
| **Devolver el `Set<Id>` de Contracts guardados** | La etapa de la Opportunity se cambia **solo** para los Contracts cuyo update salió bien. | **Usar todos los Contracts de la tanda:** avanzaríamos la Opportunity de un Contract que no tiene Renewal Quote. |
| **`== true` al leer el flag subiendo dos lookups** | Si la Opportunity no tiene Contract, el valor llega `null`, y `null == true` es false: no se manda email. | **`if ( flag )`:** con `null` tira una excepción en tiempo de ejecución. |
| **`orgUrl` calculado una vez, afuera del loop** | Es el mismo para todas las Quotes. | **Adentro del loop:** el mismo resultado, calculado N veces sin necesidad. |
| **`setSaveAsActivity( false )`** | Salesforce lo **exige** cuando el destinatario es un User (`setTargetObjectId`). | **`true`:** el envío falla con un error. |
| **`List<SObject>` en `saveLogsForFailures`** | Sirve para Contracts y Opportunities (DRY). `SObject` es el tipo base de cualquier registro, no es un genérico. | **Dos métodos casi iguales** (uno por objeto): código duplicado. |

---

## 3. Flujo paso a paso

### A) La lógica, sin código, con un ejemplo concreto (el de la prueba en el org)

SmartBytes le vende a Burlington **125 Monthly Named Users** por 12 meses: del **01/11/2025 al 31/10/2026**.

| Momento | Qué pasa en el negocio | Qué hace el sistema |
|---|---|---|
| **Mes 0** | Se gana la venta | La cadena del Req #31 crea el Contract **en Draft** con SUB-A = 125 |
| **Mes 6 (01/05/2026)** | El cliente suma 100 usuarios (Amendment) | CPQ crea SUB-B = **+100** apuntando a SUB-A |
| **Mes 9 (01/08/2026)** | El cliente baja 10 usuarios (Amendment) | CPQ crea SUB-C = **−10** apuntando a SUB-A |
| **Alguien activa el Contract** | El vendedor lo pasa a Activated | **Parte 1:** se tilda *Renewal Forecast* → CPQ crea la **Renewal Opportunity** con **215** usuarios (125 + 100 − 10) × 120 = **25.800**, en Prospecting, cierre 31/10/2026 |
| **A partir del 01/10/2026** (faltan 30 días o menos) | — | **Parte 2:** esa noche a las 3:00 el job encuentra el Contract y tilda *Renewal Quoted* → CPQ crea la **Renewal Quote** (215 usuarios, 01/11/2026 → 31/10/2027, Primary) y la Opportunity pasa a **Proposal/Price Quote** |
| **En ese mismo momento** | — | **Parte 3:** el Owner de la Quote recibe el email *"Renewal Quote created: Q-00092"* con el link |
| **Las noches siguientes** | — | El Contract ya tiene *Renewal Quoted* = true: no se vuelve a procesar |

**La regla en una frase:** al activar se pide la Opportunity; cuando faltan 30 días o menos (y todavía no se hizo) se pide la Quote y se avanza la Opportunity; cada Renewal Quote nueva avisa a su Owner.

### B) El código en orden cronológico

**Camino 1: activación (Parte 1)**

1. **Usuario** edita el Contract y pone `Status = Activated` → Guardar.
2. **`ContractTrigger`** (before update) → `ContractTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap )`.
3. → **`ContractTriggerHandler.setRenewalForecastOnActivation`**: por cada Contract compara con `Trigger.oldMap`. Si el Status **cambió** a Activated y el flag está en false → `SBQQ__RenewalForecast__c = true` en memoria (0 SOQL, 0 DML).
4. **Salesforce guarda** el Contract (con el flag).
5. **`SBQQ.ContractAfter`** (CPQ, after update) ve que el flag pasó a true → crea la **Renewal Opportunity** con sus productos (Prospecting) y completa `SBQQ__RenewalOpportunity__c` en el Contract.
6. Ese update de CPQ vuelve a disparar `ContractTrigger` → el Status ya no cambia → **no hace nada** (sin recursión).
7. **Resultado:** al refrescar el Contract se ve el link a la Renewal Opportunity.

**Camino 2: nocturno (Parte 2)**

1. **3:00** → Salesforce ejecuta el job *Renewal Quote Generation - Nightly* → **`RenewalQuoteScheduler.execute`** → `Database.executeBatch( new RenewalQuoteBatch(), BATCH_SIZE )` con `BATCH_SIZE = 1`.
2. → **`RenewalQuoteBatch.start`**: una query trae los Contracts `Activated`, con `SBQQ__RenewalQuoted__c = false` y `EndDate` entre hoy y hoy + 30.
3. Salesforce llama a **`execute`** una vez por Contract (cada uno con sus propios límites):
   - a. → **`requestRenewalQuotes`**: `SBQQ__RenewalForecast__c = true` (red de seguridad) y `SBQQ__RenewalQuoted__c = true` → **1 DML** `Database.update( lista, false )`.
     - Dentro de ese update: `ContractTrigger` no hace nada (el Status no cambió) → **`SBQQ.ContractAfter`** crea la **Renewal Quote** → se dispara el **Camino 3** (email) → CPQ encola su Queueable de cálculo.
     - Devuelve el Set de Contracts que se guardaron bien. Los que fallaron → `saveLogsForFailures` → `Error_Log__c`.
   - b. → **`updateRenewalOpportunityStage`**: si el Set está vacío → `return`. Si no, **1 SOQL** (Opportunities con `SBQQ__RenewedContract__c` en el Set y `StageName = 'Prospecting'`) → `StageName = 'Proposal/Price Quote'` → **1 DML**. Errores → `saveLogsForFailures`.
4. → **`finish`**: no hace nada.

**Camino 3: email (Parte 3)**

1. **CPQ inserta la Renewal Quote** (desde el Batch, o porque un usuario tildó *Renewal Quoted* a mano).
2. **`QuoteTrigger`** (before insert) → `QuoteTriggerHandler.beforeInsert` (DEV #1): nace en Draft → no hace nada.
3. **`QuoteTrigger`** (after insert) → **`QuoteTriggerHandler.afterInsert( Trigger.new )`** → **`sendRenewalQuoteNotifications`**:
   - a. Junta los Ids de las Quotes con `SBQQ__Type__c = 'Renewal'`. Si no hay ninguna → `return` (0 queries: el caso normal).
   - b. **1 SOQL**: nombre de la Quote, Owner, nombre del Account y de la Opportunity, y el `SBQQ__RenewalQuoted__c` del Contract que renueva (Quote → Opportunity → Contract).
   - c. **Filtro:** solo siguen las Quotes cuyo Contract tiene `SBQQ__RenewalQuoted__c == true`. La temporal que CPQ crea al activar queda afuera. Si no queda ninguna → `return`.
   - d. Por cada Quote arma un `Messaging.SingleEmailMessage`: `setTargetObjectId( OwnerId )`, `setSaveAsActivity( false )`, asunto y cuerpo de **`buildEmailBody`** (con el link `URL.getOrgDomainUrl() + '/' + Id`).
   - e. **1** `Messaging.sendEmail( lista, false )` dentro de `try`. Si un email falla, o si todo el envío tira una excepción (`catch`) → `ErrorLogUtil` → `Error_Log__c`.
4. **Resultado:** el Owner recibe *"Renewal Quote created: Q-xxxxx"* con el link. La Quote se crea igual aunque el email falle.

---

## 4. Código explicado por bloques

### `ContractTrigger`

```apex
trigger ContractTrigger on Contract ( before update ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        ContractTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    }
}
```
- **Qué hace:** mira el contexto y delega. Solo before update (sin before insert, ver sección 2).
- **Regla del training:** un trigger por objeto, `ObjetoTrigger`, sin lógica, con variables de contexto, pasando `Trigger.new` y `Trigger.oldMap` (**Módulo 2**).

### `ContractTriggerHandler`

**Bloque 1: entrada `beforeUpdate`** → llama a `setRenewalForecastOnActivation`.
- **Regla del training:** método `public static` por contexto que llama a uno `private static` (**Módulo 2**).

**Bloque 2: `setRenewalForecastOnActivation`**
```apex
Contract oldContract = oldContractByIdMap.get( newContract.Id );
Boolean statusChanged = newContract.Status != oldContract.Status;
if ( statusChanged && newContract.Status == STATUS_ACTIVATED && !newContract.SBQQ__RenewalForecast__c ) {
    newContract.SBQQ__RenewalForecast__c = true;
}
```
- **Qué hace:** solo reacciona cuando el Status **cambió** a Activated en esta transacción, y no toca lo que ya está tildado.
- **Por qué así:** before = cambio en el MISMO registro, sin DML (**Módulo 2**). `Trigger.oldMap` para correr la lógica solo si el campo cambió (**Governor Limits**). Variable `Boolean` con nombre descriptivo, `if` con llaves (**Módulo 1**). Constante `STATUS_ACTIVATED` en UPPER_CASE.
- **Recursión:** cuando CPQ (o el DEV #4, o nuestro Batch) actualiza el Contract, el Status no cambia → no hace nada. No hace falta una variable estática.

### `RenewalQuoteBatch`

**Bloque 1: `start`**
```apex
Date today = Date.today();
Date windowEndDate = today.addDays( DAYS_BEFORE_END );
return Database.getQueryLocator( [
    SELECT Id
    FROM Contract
    WHERE Status = :ContractTriggerHandler.STATUS_ACTIVATED
    AND SBQQ__RenewalQuoted__c = false
    AND EndDate >= :today
    AND EndDate <= :windowEndDate
] );
```
- **Qué hace:** la ventana (Req C). Los vencidos y los evergreen (EndDate vacío) quedan afuera.
- **Regla del training:** WHERE para traer solo lo necesario, una cláusula por línea (**Módulo 1 SOQL**). Variables `Date` tipadas usadas como bind (`:today`).
- **DRY:** el Status se compara con la constante pública del handler (`ContractTriggerHandler.STATUS_ACTIVATED`), no con una copia propia: el trigger y el Batch usan exactamente el mismo valor.

**Bloque 2: `execute`** → `requestRenewalQuotes` y después `updateRenewalOpportunityStage` con los Contracts que se guardaron bien.

**Bloque 3: `requestRenewalQuotes`**
```apex
for ( Contract con : contractList ) {
    con.SBQQ__RenewalForecast__c = true;
    con.SBQQ__RenewalQuoted__c = true;
}
List<Database.SaveResult> resultList = Database.update( contractList, false );
```
- **Qué hace:** pide la Quote a CPQ (Req D). `RenewalForecast` como red de seguridad para Contracts activados antes del trigger (por ejemplo, 00000100 a 00000105).
- **Por qué así:** una sola DML sobre la lista (**Módulo 1, Governor Limits**). `allOrNone = false`: si uno falla, el resto sigue y el error queda en `Error_Log__c` (**Módulo 3**, sin fallar en silencio). Si CPQ falla al crear la Quote, el update de ese Contract falla, el flag queda en false y **la noche siguiente se reintenta**.

**Bloque 4: `updateRenewalOpportunityStage`**
```apex
if ( quotedContractIdSet.isEmpty() ) { return; }
for ( Opportunity opp : [
    SELECT Id, StageName
    FROM Opportunity
    WHERE SBQQ__RenewedContract__c IN :quotedContractIdSet
    AND StageName = :STAGE_PROSPECTING
] ) { ... }
```
- **Qué hace:** Req E. Usa el campo `SBQQ__RenewedContract__c` (lo completa CPQ) para encontrar la Renewal Opportunity.
- **Regla del training:** condicional antes de la SOQL, `Set<Id>` para bulkificar, for con SOQL, una sola DML (**Governor Limits, Módulo 1**).

**Bloque 5: `saveLogsForFailures`**
- **Qué hace:** recorre los `SaveResult` por posición (un resultado fallido no trae el Id) y guarda los Error Logs con un solo insert.
- **Por qué así:** lo usan los dos updates (**DRY**). Recibe `List<SObject>` (el tipo base de cualquier registro, no es un genérico) para servir para Contracts y Opportunities.

**Bloque 6: `finish`** vacío, porque la interfaz lo exige.
- **Regla del training:** Batch para volumen (**Módulo 4**). Sin `Database.Stateful`.

### `RenewalQuoteScheduler`
```apex
public static final String JOB_NAME = 'Renewal Quote Generation - Nightly';
public static final String CRON_EXPRESSION = '0 0 3 * * ?';
public static final Integer BATCH_SIZE = 1;
public void execute( SchedulableContext sc ) {
    Database.executeBatch( new RenewalQuoteBatch(), BATCH_SIZE );
}
```
- **Regla del training:** `Schedulable` que delega en otra clase (**Módulo 4**). El tamaño de tanda en una constante con nombre que explica el porqué.

### `QuoteTrigger` (lo agregado)
```apex
trigger QuoteTrigger on SBQQ__Quote__c ( before insert, before update, after insert ) {
    ...
    } else if ( Trigger.isAfter && Trigger.isInsert ) {
        QuoteTriggerHandler.afterInsert( Trigger.new );
    }
}
```
- **Por qué after:** el link necesita el Id, que en before insert todavía no existe (**Módulo 2**). Sigue siendo **un solo trigger por objeto**: no se creó otro trigger de Quote.

### `QuoteTriggerHandler` (lo agregado)

**Bloque 1: filtro + condicional antes de la SOQL**
```apex
for ( SBQQ__Quote__c newQuote : newQuoteList ) {
    if ( newQuote.SBQQ__Type__c == TYPE_RENEWAL ) {
        renewalQuoteIdSet.add( newQuote.Id );
    }
}
if ( renewalQuoteIdSet.isEmpty() ) { return; }
```
- **Por qué así:** la mayoría de las Quotes no son Renewal: con este `return` no gastan ninguna query (**Governor Limits**).

**Bloque 2: query + filtro de la Quote temporal**
```apex
List<SBQQ__Quote__c> quoteList = [
    SELECT Id, Name, OwnerId, SBQQ__Account__r.Name, SBQQ__Opportunity2__r.Name,
        SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c
    FROM SBQQ__Quote__c
    WHERE Id IN :renewalQuoteIdSet
];
for ( SBQQ__Quote__c quote : quoteList ) {
    if ( quote.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c == true ) {
        renewalQuoteList.add( quote );
    }
}
if ( renewalQuoteList.isEmpty() ) { return; }
```
- **Qué hace:** trae los nombres para el email y el flag del Contract que renueva, y se queda solo con las Quotes **pedidas**.
- **Por qué así:** relaciones lookup para datos de los padres, incluso subiendo dos niveles (**Módulo 1 SOQL**). Una sola query para todas. Se compara con `== true` porque si la Opportunity no tiene Contract el valor llega `null`, y `null` también tiene que contar como "no mandar".

**Bloque 3: armado de los emails**
```apex
email.setTargetObjectId( renewalQuote.OwnerId );
email.setSaveAsActivity( false );
email.setSubject( 'Renewal Quote created: ' + renewalQuote.Name );
email.setPlainTextBody( buildEmailBody( renewalQuote, orgUrl ) );
```
- **Por qué así:** `targetObjectId` con un User no consume el límite diario. Con un User como destinatario, Salesforce exige `setSaveAsActivity( false )`. `orgUrl` se calcula una sola vez, afuera del loop.

**Bloque 4: envío con try/catch**
```apex
try {
    List<Messaging.SendEmailResult> resultList = Messaging.sendEmail( emailList, false );
    ... // por posición: si uno falló -> Error Log
} catch ( Exception e ) {
    ... // un Error Log por Quote
}
ErrorLogUtil.saveLogs( errorLogList );
```
- **Por qué así:** un solo `sendEmail` para todas (límite: 10 por transacción, como "no DML en loops"). try/catch sin fallar en silencio (**Módulo 3**): una excepción sin atrapar haría rollback de la Renewal Quote que está creando CPQ (**Governor Limits**: "una excepción no atrapada hace rollback de toda la transacción").

**Bloque 5: `buildEmailBody`**: concatena el texto con el nombre de la Quote, el Account, la Opportunity y el link `orgUrl + '/' + Id`, que en Lightning abre el registro.

### `TestDataFactory` (lo agregado)
- **`buildContracts( accountId, startDate, contractTerm, n )`:** N Contracts en Draft sin insertar (para el bulk de 200). `createContract` ahora lo reutiliza (DRY).
- **`buildRenewalOpportunities( accountId, contractList, stageName )`:** Opportunities como las de CPQ (`SBQQ__Renewal__c`, `SBQQ__RenewedContract__c`).

### `SBQQ.TriggerControl.disable()` (solo en 2 tests bulk)
- **Qué es:** un método global del paquete CPQ que apaga **sus** triggers durante la transacción del test. Los nuestros siguen corriendo. El test hace rollback al terminar, así que no afecta al org.
- **Por qué hizo falta:** primero corrimos todo sin él. Pasaron 23 de 25, y los 2 bulk fallaron con **`SBQQ: Too many SOQL queries: 101`**: el prefijo `SBQQ:` indica que el límite lo rompe el código de CPQ al generar 200 Renewal Opportunities juntas. Nuestro trigger usa 0 queries. Un test bulk mide **nuestra** bulkificación. Lo que crea CPQ se probó en el org, y los demás tests corren con CPQ prendido.
- **Fuera del curso:** sí. Es la alternativa más simple que encontramos y se usa **solo** en `ContractTriggerHandlerTest.activationBulkTest` y `RenewalQuoteBatchTest.bulkTest`.

---

## 5. Supuestos y decisiones

Confirmadas por Francisco (02/10/2026 y 05/10/2026):

1. **Tildar los flags nativos de CPQ** en lugar de crear los registros a mano.
2. **Parte 1 en before update.** Se iba a sumar before insert, pero se sacó al verificar que Salesforce no deja insertar un Contract Activated (`FAILED_ACTIVATION`).
3. **Ventana:** Activated, `SBQQ__RenewalQuoted__c = false`, `hoy <= EndDate <= hoy + 30`. Los vencidos y los evergreen no se tocan. El Batch tilda `RenewalForecast` si falta.
4. **"Actualizar la Renewal Opportunity" = `StageName` de `Prospecting` a `Proposal/Price Quote`**, en el Batch y **solo** si sigue en Prospecting.
5. **Email** en el after insert del `QuoteTrigger`, para **toda** Quote de tipo Renewal (también las generadas a mano), armado en Apex, al Owner, con try/catch + Error Log.
6. **Job a las 3:00**, Batch con **tamaño 1**.
7. **Activación manual** del Contract en la demo (no se tocó el IC).
8. **Sin backfill** de los Contracts 00000100 a 00000105 (activados antes del trigger y sin Renewal). El Batch los va a tomar cuando les falten 30 días (red de seguridad).
9. **Paso 0** autorizado sobre el Contract 00000107 (no el 00000108).
10. **`SBQQ.TriggerControl.disable()`** solo si hacía falta y solo en tests: hizo falta en los 2 tests bulk.
11. **Contract "DEV3 Demo"** armado después del deploy y la prueba.
12. **Filtro de la Quote temporal de CPQ (opción A, 05/10/2026):** el email solo sale si el Contract que renueva la Quote tiene `SBQQ__RenewalQuoted__c = true`. Supuestos verificados en el org antes de programar. Probado con el Contract "DEV3 Fix Test" (00000111).

**Otros supuestos:**
- **Owner de la Quote:** CPQ le pone el Owner de la Renewal Opportunity, que es el de la Opportunity original (verificado).
- **"Hoy"** = `Date.today()` en la zona horaria del usuario que programó el job (America/Los_Angeles).
- **Un Contract que se activa con menos de 30 días por delante** recibe su Renewal Quote la noche siguiente (como máximo 1 día de demora).
- **Texto del email en inglés** (es un mensaje para el usuario del cliente). Texto plano, sin template.
- **`with sharing`:** el job y el usuario de la demo son admin, y el sharing de Contract es Public Read/Write.

---

## 6. Edge cases

| Caso | Cómo se maneja | Test |
|---|---|---|
| Contract Draft → Activated | Se tilda Renewal Forecast | `activationSetsRenewalForecastTest` |
| 200 Contracts activados juntos | Los 200 tildados, 0 queries nuestras | `activationBulkTest` |
| Draft → In Approval Process | No se tilda | `otherStatusDoesNotSetForecastTest` |
| Se edita otro campo, sin cambiar el Status | No se tilda | `otherFieldUpdateDoesNotSetForecastTest` |
| Contract ya activado al que se le edita otro campo (DEV #4, CPQ, el Batch) | No se reprocesa (sin recursión) | `alreadyActivatedNotReprocessedTest` |
| Insertar un Contract ya Activated | Salesforce no lo permite (`FAILED_ACTIVATION`) | Verificado en el org (sección 2) |
| Vence dentro de 19 días | Renewal Quoted tildado | `contractInWindowQuotedTest` |
| Vence hoy / en exactamente 30 días | Entran | `windowBoundaryTest` |
| Vence en 31 días / venció ayer | No entran | `windowBoundaryTest` |
| Contract en Draft dentro de la ventana | No se procesa | `draftContractNotQuotedTest` |
| Contract evergreen (sin fin) | No se procesa | `evergreenContractNotQuotedTest` |
| Activado sin Renewal Forecast (anterior al deploy) | El Batch tilda los dos flags | `missingForecastSafetyNetTest` |
| Renewal Opportunity en Prospecting | Pasa a Proposal/Price Quote | `opportunityStageUpdatedTest` |
| Renewal Opportunity que ya avanzó (Negotiation/Review) | No se toca | `opportunityStageUpdatedTest` |
| Contract ya procesado (Renewal Quoted = true) | No se vuelve a procesar | `alreadyQuotedNotReprocessedTest` |
| 200 Contracts en la ventana | 200 tildados y 200 Opportunities actualizadas | `bulkTest` |
| El job falla una noche | La noche siguiente lo toma (ventana `<=`) | Por diseño (`windowBoundaryTest` prueba la ventana) |
| CPQ falla al crear la Quote | El update de ese Contract falla → Error Log; el flag queda en false → se reintenta la noche siguiente | Sin test (no se puede forzar a CPQ) |
| El Scheduler se programa y lanza el Batch | Cron `0 0 3 * * ?` + 1 Batch | `scheduleNightlyJobTest` |
| El job real ya existe con el mismo nombre | El test usa `JOB_NAME + ' (Test)'` | `scheduleNightlyJobTest` |
| Nace una Renewal Quote | 1 envío de email, 0 errores | `renewalQuoteSendsEmailTest` |
| Nacen 200 Renewal Quotes juntas | **1** envío (con 200 emails), no 200 | `renewalQuoteBulkEmailTest` |
| Nace una Quote que no es Renewal | No hay email | `nonRenewalQuoteNoEmailTest` |
| Nace una Renewal Quote cuyo Contract no tiene Renewal Quoted (la **temporal** que CPQ crea al activar) | No hay email | `renewalQuoteNotRequestedNoEmailTest` + prueba en el org (00000111: activación con 0 emails encolados) |
| CPQ inserta y deshace una Renewal Quote en la misma transacción | Su rollback descarta el email encolado | Observado en el org (Q-00089, Q-00091, Q-00105, Q-00107) |
| Se tildan los dos flags en el mismo save (red de seguridad del Batch) | **Caso gris:** si CPQ crea su temporal en ese save, el flag ya está en true y su email saldría. Ver sección 10 | Sin test (depende de CPQ) |
| Falla un email (por ejemplo, Owner inactivo) o el envío entero (Deliverability apagado) | Error Log; la Quote se crea igual | Sin test (en test no se puede hacer fallar `sendEmail`) |
| Activar cientos de Contracts juntos (Data Loader) | Falla **por CPQ** (límite de queries dentro de su código) | `activationBulkTest` sin `TriggerControl` lo mostró. Ver sección 10 |

---

## 7. Preguntas probables del Code Review

**1. ¿Por qué tildaste los flags de CPQ en vez de crear la Opportunity y la Quote?**
Porque CPQ ya sabe armar una renovación: combina las cantidades de los Amendments (125 + 100 − 10 = 215), aplica precios, deja la Quote Primary y la vincula con el Contract. Reimplementar eso sería mucho código y fácil de equivocar. Lo verificamos en el org antes de programar (Paso 0).

**2. ¿Por qué la Parte 1 está en before update y no en after?**
Porque lo único que hacemos es cambiar un campo del mismo Contract. En before se asigna en memoria y Salesforce lo guarda en el mismo save, sin DML. Después, en el after de ese mismo save, el trigger de CPQ ve el flag y crea la Opportunity. En after necesitaríamos otro `update` del Contract, que vuelve a disparar todos los triggers.

**3. ¿Por qué no hay before insert?**
Lo probamos: Salesforce no deja insertar un Contract ya Activated (`FAILED_ACTIVATION`). La activación siempre es un update, así que un before insert nunca correría y ningún test lo podría cubrir.

**4. ¿Cómo evitás la recursión? CPQ y el DEV #4 también actualizan el Contract.**
Comparando con `Trigger.oldMap`: solo actuamos si el Status cambió a Activated en esa transacción. Cuando CPQ escribe la Renewal Opportunity, o el DEV #4 el contador, el Status no cambia y el trigger no hace nada. No hace falta una variable estática.

**5. ¿Por qué un Batch y no un trigger para los 30 días?**
Porque que falten 30 días no es un guardado: es el calendario que avanza. Un trigger solo corre cuando alguien guarda algo. Es el mismo patrón del DEV #1 y del DEV #4: Scheduler a las 3:00 + Batch.

**6. ¿Por qué "EndDate <= hoy + 30" y no "= hoy + 30"?**
Para que el proceso sea tolerante a fallas: si el job no corre una noche, o si un Contract se activa cuando le quedan 20 días, la noche siguiente lo procesa igual. El flag `SBQQ__RenewalQuoted__c = true` marca "ya procesado", así que nunca se genera dos veces.

**7. ¿Por qué el Batch corre de a 1 Contract?**
Porque lo vimos en el org: CPQ encola un Queueable de cálculo por cada Renewal Quote, y desde un `execute` de Batch solo se puede encolar uno. Además, cada Contract tiene sus propios governor limits. Como por noche entran pocos Contracts, no hay problema de velocidad.

**8. ¿Por qué el email está en el trigger de Quote y no en el Batch?**
Porque la Quote la crea CPQ y el link necesita su Id: en el after insert de la Quote lo tenemos sin buscarlo. Además avisa por cualquier Renewal Quote, la genere el Batch o un usuario a mano. Se manda un solo `sendEmail` para todas las Quotes.

**9. ¿Qué pasa si falla el envío del email?**
Está dentro de un try/catch. Como corre dentro del save en el que CPQ crea la Quote, una excepción sin atrapar haría rollback de la Renewal Quote. Lo atrapamos y lo guardamos en `Error_Log__c`: la Quote se crea igual y el error queda registrado.

**10. ¿Te preocupa el límite de 15 emails por día del org?**
No, porque usamos `setTargetObjectId` con el Id de un usuario interno, y esos emails no cuentan para el límite diario. Sí respetamos el límite de 10 envíos por transacción con un solo `sendEmail` por transacción (lo prueba el test bulk de 200).

**11. ¿Por qué usaste `SBQQ.TriggerControl.disable()` en los tests? ¿No es hacer trampa?**
Solo en los 2 tests bulk. Sin eso fallaban con `SBQQ: Too many SOQL queries`: el límite lo rompía el código de CPQ al generar 200 renovaciones juntas, no el nuestro (0 queries). El test bulk mide nuestra bulkificación. Los demás tests corren con CPQ prendido, y lo que crea CPQ se probó en el org.

**12. ¿Cómo se reflejan los Amendments en la renovación?**
CPQ arma la Renewal Opportunity y la Quote desde todas las Subscriptions del Contract, combinando las revisiones con su original. En el org: 125 + 100 − 10 → **una línea de 215** en la Opportunity (25.800) y en la Quote Q-00092.

**13. ¿Por qué el email mira el flag del Contract y no solo el Type de la Quote?**
Porque al activar un Contract, CPQ crea una Renewal Quote temporal para calcular la Renewal Opportunity y la borra segundos después. Es idéntica a una real, y en la primera prueba mandamos un email con un link muerto. Solo avisamos si el Contract tiene `RenewalQuoted = true`, o sea, si alguien pidió la Quote. Lo verificamos en el org antes de programar.

**14. ¿Qué cambia en la Renewal Opportunity a los 30 días?**
CPQ le pone la Renewal Quote como Primary y sincroniza productos y Amount. Nosotros además la pasamos de Prospecting a Proposal/Price Quote, solo si sigue en Prospecting, para no pisar lo que haya avanzado un vendedor.

**15. ¿Por qué el Batch usa `ContractTriggerHandler.STATUS_ACTIVATED` y no su propia constante?**
Por DRY: el valor `'Activated'` tiene que estar definido en un solo lugar. Si el Batch tuviera su copia y alguien cambiara una sola, el trigger y el Batch dejarían de coincidir sin ningún error de compilación. Es el mismo patrón del DEV #2, donde el Queueable usa `OrderTriggerHandler.STATUS_DRAFT`. La constante vive en el handler porque es el "dueño" de la regla de activación del Contract. Al principio había una copia en el Batch; se unificó al congelar el código y se corrieron todos los tests de nuevo.

---

## 8. Cómo se prueba en la demo

**Datos preparados:** Contract **00000110** (Opportunity "DEV3 Demo - Renewal", Q-00093), **en Draft**, 01/11/2025 → 31/10/2026, con SUB-0000017 (125), SUB-0000018 (+100 desde 01/05/2026, Q-00094) y SUB-0000019 (−10 desde 01/08/2026, Q-00095). *Active Subscriptions* = 1.

> ⚠️ El Contract tiene que vencer **dentro de los 30 días** del día de la demo. El 00000110 sirve para una demo **hasta el 31/10/2026**. Si la demo es más tarde, hay que armar otro con los scripts `scripts/apex/dev3-1/2/3-*.apex` y un `START_DATE` más nuevo (ver el encabezado de cada script).

### A. Parte 1: la activación
1. Abrir el Contract **00000110**. Mostrar: Status **Draft**, *Renewal Forecast* destildado, *Renewal Opportunity* vacío, related list Subscriptions con los 3 registros (explicar los Amendments).
2. **Edit → Status = Activated → Save.**
3. **Tiene que verse** (al instante, no hace falta esperar): *Renewal Forecast* tildado y *Renewal Opportunity* con link.
4. Abrir la Renewal Opportunity: **Prospecting**, Close Date 31/10/2026, producto Monthly Named Users × **215**, Amount **25.800**. Explicar que 215 = 125 + 100 − 10. Si el Amount todavía muestra otro valor, esperar 5 segundos y refrescar: CPQ calcula los precios en un Queueable.
5. **En este paso NO tiene que llegar ningún email.** Si preguntan por qué: al activar, CPQ crea una Renewal Quote temporal para calcular la Opportunity y la borra a los pocos segundos. Nuestro filtro (`SBQQ__RenewalQuoted__c` del Contract en false) evita avisar por ella. Es el "Hallazgo" de la sección 2.
6. *(Opcional, para mostrar el hallazgo)* Related list **Quotes** de la Renewal Opportunity: no queda ninguna Quote. La temporal ya se borró (está en la Papelera).

### B. Parte 2: los 30 días
1. *Setup → Scheduled Jobs*: mostrar **Renewal Quote Generation - Nightly**, próxima ejecución a las 3:00.
2. Para no esperar a la noche: **Developer Console → Execute Anonymous**:
   ```apex
   Database.executeBatch( new RenewalQuoteBatch(), RenewalQuoteScheduler.BATCH_SIZE );
   ```
3. *Setup → Apex Jobs*: `RenewalQuoteBatch` **Completed** (1 ítem, 0 errores).
4. Volver al Contract: *Renewal Quoted* tildado.
5. Abrir la Renewal Opportunity: **Proposal/Price Quote** y Primary Quote = la Renewal Quote nueva.
6. Abrir la Quote: Type **Renewal**, Draft, Primary, 01/11/2026 → 31/10/2027, 1 línea de **215**.

### C. Parte 3: el email
1. Abrir el inbox del Owner (frandev → fpistone@firstchairservices.com). Tenerlo abierto **antes** de correr el Batch del punto B.2: el email llega a los pocos segundos.
2. **Tiene que verse UN solo email:** *"Renewal Quote created: Q-xxxxx"* (el mismo número de la Quote del punto B.6), con el Account, la Opportunity y el link. Ningún email de la activación (punto A.5).
3. Hacer clic en el link: abre la Quote en Lightning.
4. Tab **Error Logs**: vacía.

### Notas para la demo
- **Orden recomendado:** A (activar) → esperar 5 s → mostrar la Opportunity con 215 → B (Batch) → C (email). Esperar a que termine el cálculo de CPQ antes de correr el Batch es una precaución (no probamos qué pasa si se pide la Quote en el medio): en todas las pruebas lo hicimos así y salió bien.
- **Usuario:** hacerla con frandev (admin). Con un usuario Direct Sales todavía no se probó la activación (QA-DEV3-03).
- **Si algo falla en vivo:** revisar *Setup → Apex Jobs* (`RenewalQuoteBatch`, `QueueableCalculatorService`) y la tab **Error Logs**. Plan B: mostrar la evidencia ya generada, con el Contract **00000109** (Q-00092) o el **00000111** (Q-00108).
- **Si en Apex Jobs aparece un `QueueableCalculatorService` en Failed** con *"The system can't process API calls currently"*: es un cálculo duplicado de CPQ, no un error nuestro (sección 10, punto 9).
- **Fecha límite:** el 00000110 sirve hasta el 31/10/2026 (ver el aviso de arriba). Para una demo posterior, armar otro Contract con los scripts y correr los 3 pasos. Cada script dice en su encabezado qué completar.
- **Frase para explicar el diseño en 20 segundos:** "No creamos los registros a mano: tildamos los flags nativos de CPQ en el momento justo. Al activar, la Renewal Opportunity; a los 30 días, la Renewal Quote. CPQ arma todo con los Amendments incluidos, y nosotros avisamos al Owner solo cuando la Quote fue pedida de verdad."

### Evidencia real en el org (05/10/2026)

| Prueba | Resultado |
|---|---|
| Paso 0 (Contract 00000107, flags a mano, antes del deploy) | Renewal Opportunity en el mismo save (Prospecting, 125) y **Q-00085** (Renewal, Primary, Owner frandev). Sin email: el código todavía no estaba deployado |
| E2E: Contract **00000109** ("DEV3 E2E Test - Renewal", Q-00086 → Order 00000123) | Amendments Q-00087 (+100 desde 01/05/2026 → Order 00000124 → SUB-0000015) y Q-00088 (−10 desde 01/08/2026 → Order 00000125 → SUB-0000016) |
| Parte 1 en vivo (update solo del Status) | Nuestro trigger tildó el flag → Renewal Opportunity con **215 × 120 = 25.800**, Prospecting, cierre 31/10/2026 |
| Parte 2 en vivo (Batch a mano, tamaño 1) | Batch Completed 1/1, 0 errores → **Q-00092** (Renewal, Primary, Owner frandev, 01/11/2026 → 31/10/2027, 1 línea de 215) y Opportunity en **Proposal/Price Quote**. CPQ encoló 1 Queueable de cálculo desde el Batch: Completed |
| Parte 3 en vivo | `sendEmail` sin errores, 0 Error Logs. Llegaron 2 emails: Q-00092 (link OK) y **Q-00090** (link muerto: la Quote temporal de CPQ). Ver "Hallazgo" en la sección 2 |
| Fix Test: Contract **00000111** ("DEV3 Fix Test - Renewal", Q-00096 → Order) | Activación: 2 inserts de Renewal Quote y **0 emails encolados** (debug log). La temporal Q-00106 se borró a los 5 s. Batch: Completed 1/1 → **Q-00108** (Renewal, Primary) + Opportunity en Proposal/Price Quote + **1 email**. 0 Error Logs. **Confirmado por Francisco en Gmail:** llegó solo el email de Q-00108 y el link funciona |
| Job programado | *Renewal Quote Generation - Nightly*, `0 0 3 * * ?`, WAITING (próxima: 06/10/2026 3:00 America/Los_Angeles) |
| Demo | Contract **00000110** preparado en Draft (Q-00093 → Order 00000126; Q-00094 → Order 00000127 → SUB-0000018; Q-00095 → Order 00000128 → SUB-0000019) |
| Observación de CPQ | En los Amendments, CPQ encoló 2 o 3 `QueueableCalculatorService` en paralelo para la misma Quote: uno Completed, los duplicados **Failed** con *"The system can't process API calls currently"*. Las Quotes quedaron bien calculadas. No es nuestro código |

---

## 9. Tests, cobertura y Build Tracker

### C) Tests del DEV #3 (18 nuevos, todos pasan)

**`ContractTriggerHandlerTest`** (setup: Account)

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `activationSetsRenewalForecastTest` | Positivo | Contract en Draft | Status → Activated | Renewal Forecast = true |
| `activationBulkTest` | Bulk | 200 Contracts en Draft, CPQ apagado | Los activa juntos | Los 200 con Renewal Forecast |
| `otherStatusDoesNotSetForecastTest` | Negativo | Contract en Draft | Status → In Approval Process | Renewal Forecast = false |
| `otherFieldUpdateDoesNotSetForecastTest` | Negativo | Contract en Draft | Edita Description | Renewal Forecast = false |
| `alreadyActivatedNotReprocessedTest` | Negativo | Contract activado con el flag destildado | Edita Description | Sigue en false |

**`RenewalQuoteBatchTest`** (setup: Account. Contracts de 12 meses con la EndDate pedida)

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `contractInWindowQuotedTest` | Positivo | Activado, vence en 19 días | Corre el Batch | Renewal Quoted y Forecast = true |
| `windowBoundaryTest` | Borde | Vencen hoy, en 30, en 31 y ayer | Corre el Batch | Hoy y 30 sí; 31 y ayer no |
| `draftContractNotQuotedTest` | Negativo | Draft, vence en 19 días | Corre el Batch | Renewal Quoted = false |
| `evergreenContractNotQuotedTest` | Negativo | Activado sin plazo | Corre el Batch | Renewal Quoted = false |
| `missingForecastSafetyNetTest` | Positivo | Activado, Forecast destildado | Corre el Batch | Los dos flags = true |
| `opportunityStageUpdatedTest` | Positivo + negativo | 2 Contracts: Opportunity en Prospecting y en Negotiation/Review | Corre el Batch | Proposal/Price Quote y Negotiation/Review sin cambios; 0 Error Logs |
| `alreadyQuotedNotReprocessedTest` | Negativo | Activado con Renewal Quoted = true + Opportunity en Prospecting | Corre el Batch | La Opportunity sigue en Prospecting |
| `bulkTest` | Bulk | 200 Contracts en la ventana con su Opportunity, CPQ apagado | Corre el Batch (tanda de 200) | 200 Renewal Quoted y 200 Opportunities en Proposal/Price Quote |

**`RenewalQuoteSchedulerTest`**

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `scheduleNightlyJobTest` | Positivo | Nombre de job de test | `System.schedule` + `stopTest` | Cron `0 0 3 * * ?` y 1 Batch lanzado |

**`QuoteTriggerHandlerTest`** (4 tests nuevos; los 8 del DEV #1 siguen pasando. Las Renewal Quotes se cuelgan de una Renewal Opportunity cuyo Contract tiene Renewal Quoted en true o en false, armados antes de `Test.startTest()`)

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `renewalQuoteSendsEmailTest` | Positivo | Contract con Renewal Quoted = true | Inserta 1 Quote Renewal | 1 envío, 0 Error Logs |
| `renewalQuoteBulkEmailTest` | Bulk | Contract con Renewal Quoted = true | Inserta 200 Quotes Renewal | **1** envío, 0 Error Logs |
| `nonRenewalQuoteNoEmailTest` | Negativo | — | Inserta 1 Quote común | 0 envíos |
| `renewalQuoteNotRequestedNoEmailTest` | Negativo | Contract con Renewal Quoted = **false** (la temporal de CPQ) | Inserta 1 Quote Renewal | 0 envíos, 0 Error Logs |

**Notas de testing:**
- `Limits.getEmailInvocations()` se lee **antes** de `Test.stopTest()`. En test los emails no salen, pero Salesforce cuenta las llamadas.
- En los tests el Batch se lanza con tamaño **200** y no con 1: en un test `execute()` corre una sola vez, así que con tamaño 1 solo procesaría un Contract. El tamaño real (1) lo usa el Scheduler.
- Los tests no verifican lo que crea CPQ (es código del paquete): eso se probó en el org (sección 8).

### Cobertura (corrida del 05/10/2026, todos los tests locales)

**71 métodos de test, 71 pasan** (corrida de las 15:46 UTC, después del filtro). Salesforce informa "79" porque cuenta el `@testSetup` de cada una de las 8 clases que lo tienen. **Cobertura del org: 96%.**

**Re-corrida del congelamiento del código (05/10/2026 19:14 UTC, Test Run `707fj000016kYIt`):** con el Batch usando `ContractTriggerHandler.STATUS_ACTIVATED` y los comentarios en inglés, **83/83 métodos pasan** (todo el org, con el DEV #5) y la cobertura no cambió. Solo se corrieron los números de las líneas sin cubrir de `RenewalQuoteBatch` (de 122/138/155-156 a 123/139/156-157), por el comentario nuevo y la constante que se sacó.

| Clase / Trigger | Líneas cubiertas | Cobertura | Sin cubrir y por qué |
|---|---|---|---|
| `ContractTrigger` | 2/2 | 100% | — |
| `ContractTriggerHandler` | 8/8 | 100% | — |
| `RenewalQuoteBatch` | 40/44 | 91% | **123:** `return` cuando **todos** los updates de Contract fallan. **139:** `return` de seguridad cuando no hay ninguna Opportunity en Prospecting (en los tests CPQ siempre crea una al activar). **156-157:** arman el Error Log cuando falla un update. Con datos normales de test no se puede hacer fallar el update (mismo caso que el DEV #1 y el DEV #4). |
| `RenewalQuoteScheduler` | 3/3 | 100% | — |
| `QuoteTrigger` | 6/6 | 100% | — |
| `QuoteTriggerHandler` | 64/70 | 91% | **205-206:** Error Log cuando falla un email individual. **209-213:** el `catch` (por ejemplo, Deliverability apagado). En un test no se puede hacer fallar `Messaging.sendEmail`. |

### Build Tracker

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| ContractTrigger | ContractTriggerHandlerTest | 05/10/2026 | 100% |
| ContractTriggerHandler | ContractTriggerHandlerTest (+ RenewalQuoteBatchTest) | 05/10/2026 | 100% |
| RenewalQuoteBatch | RenewalQuoteBatchTest | 05/10/2026 | 91% |
| RenewalQuoteScheduler | RenewalQuoteSchedulerTest | 05/10/2026 | 100% |
| QuoteTrigger | QuoteTriggerHandlerTest | 05/10/2026 | 100% |
| QuoteTriggerHandler | QuoteTriggerHandlerTest | 05/10/2026 | 91% |

---

## 10. Limitaciones conocidas y pendientes de QA

1. **Ramas de error sin cubrir** (`RenewalQuoteBatch` 123, 139, 156-157; `QuoteTriggerHandler` 205-206, 209-213). Ver sección 9.
2. **Activación masiva:** activar muchos Contracts en una sola transacción (por ejemplo, 200 con Data Loader) falla con `SBQQ: Too many SOQL queries`, **por el código de CPQ**, no por el nuestro. Recomendación: activar en tandas chicas (Data Loader con batch size bajo).
3. **Hasta 1 día de demora:** un Contract que se activa con menos de 30 días por delante recibe su Renewal Quote la noche siguiente.
4. **Contracts vencidos** (EndDate < hoy) no reciben Renewal Quote automática.
5. **Contracts 00000100 a 00000105:** activados antes del trigger y sin Renewal Opportunity. No se hizo backfill (decisión 8). El Batch se las crea cuando les falten 30 días.
6. **Email:** texto fijo en Apex (en inglés, texto plano). Cambiar el texto requiere un deploy. Si el Owner de la Quote fuera una Queue o un usuario inactivo, el email falla y queda en Error Logs.
7. **Etapa:** solo se mueve desde Prospecting. Una Renewal Opportunity que un vendedor ya movió a otra etapa no se toca (a propósito).
8. **Hora del job:** 3:00 America/Los_Angeles (zona del usuario que lo programó). Si ese usuario se desactiva, el job deja de correr.
9. **Cálculos duplicados de CPQ:** en los Amendments CPQ encola cálculos en paralelo y los duplicados quedan Failed en Apex Jobs (*"The system can't process API calls currently"*). Las Quotes quedan bien calculadas.
10. **Demo con fecha:** el Contract 00000110 entra en la ventana solo hasta el 31/10/2026.
11. **Lección de deploy:** se desplegaron solo los archivos nuevos o cambiados.
12. **Caso gris de los dos flags en el mismo save:** cuando el Batch procesa un Contract que **no** tenía Renewal Forecast (activado antes del trigger, como 00000100 a 00000105), tilda los dos flags en el mismo update. Si en ese save CPQ crea también su Renewal Quote temporal, nuestro filtro ve `RenewalQuoted = true` y su email saldría con un link que después muere. No se probó (dejaría un Contract real con su renovación generada). En el flujo normal no pasa, porque la activación y los 30 días son transacciones separadas. Si ocurre, el Owner recibe un email extra; la Quote real y su email salen bien.
13. **Dependencia del comportamiento interno de CPQ:** la Quote temporal, su borrado y el rollback interno son lógica del paquete (oculta en los logs). Si una versión futura de CPQ cambia ese mecanismo, hay que volver a verificar el filtro.
14. ~~**Constante duplicada:** `STATUS_ACTIVATED` estaba definida en `ContractTriggerHandler` y en `RenewalQuoteBatch`.~~ ✅ **Resuelto el 05/10/2026 (congelamiento del código):** el Batch ahora usa `ContractTriggerHandler.STATUS_ACTIVATED`. Mismo comportamiento: se corrieron todos los tests del org después del cambio (ver sección 9).

Pendientes de QA (detalle en [`docs/qa-pending.md`](../qa-pending.md)):
- ~~**QA-DEV3-01:** recepción del email y que el link abra la Quote.~~ ✅ **Cerrado el 05/10/2026:** llegaron Q-00092 y Q-00108 con su link funcionando, y la activación ya no manda el email de la Quote temporal.
- **QA-DEV3-02:** el job nocturno procesa un Contract solo (sin correr el Batch a mano).
- **QA-DEV3-03:** activación desde la UI con un usuario Direct Sales.
- **QA-DEV3-04:** Amendment **después** de activar: ¿CPQ actualiza la Renewal Opportunity?

También verificado: el trigger del DEV #4 (`SubscriptionTrigger`) corrió en vivo dentro del contracting de CPQ al crear los Contracts 00000109 y 00000110 (*Active Subscriptions* = 1). Es evidencia parcial para QA-DEV4-01.
