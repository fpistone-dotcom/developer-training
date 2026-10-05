# Pruebas pendientes para QA

## QA-DEV2-01 — Activación de una Order que nace con `Not Needed` (camino del Queueable)

**Requirement:** DEV #2, parte (B) "whenever it is created".
**Estado:** pendiente. Cubierto por tests unitarios (`activateOnInsertTest`, `activateOnInsertBulkTest`), pero sin prueba en vivo en el org.

### Por qué hace falta esta prueba
En el flujo estándar de CPQ la Order nace con `Not Started` y la activa el `before update` (verificado con debug log el 29/09/2026, ver [`code-review/DEV2.md`](code-review/DEV2.md)). El camino del Queueable solo se ejecuta cuando la Order **se crea ya lista**, por ejemplo por una carga manual, Data Loader o una integración. Ese camino todavía no se probó en el org real.

### Riesgo principal a verificar: "Too many queueable jobs"
Cuando `OrderActivationQueueable` activa la Order, en **esa misma transacción async** se dispara el Flow 2 (Contracted), y CPQ encola su job de contracting (`QueueableContractOrdersClient`). **Desde un contexto async solo se puede encolar 1 job.**

- Nuestro Queueable no encola nada, así que ese único cupo lo debería usar CPQ.
- Si CPQ (u otra automatización disparada por la activación) intenta encolar más de un job, la transacción puede fallar con `System.LimitException: Too many queueable jobs added to the queue`.

**Qué pasa si ocurre:**
- Si el error queda asociado a la Order, `Database.update( lista, false )` lo devuelve en el `SaveResult` y se registra en **Error Logs**.
- Si es una Limit Exception que corta el job completo (no se puede atrapar), **no** va a haber Error Log: el job de `OrderActivationQueueable` aparece como **Failed** en *Apex Jobs*.

Por eso hay que revisar **las dos cosas**: Error Logs y Apex Jobs.

### Precondiciones
- Código del DEV #2 deployado en el org (`OrderTrigger`, `OrderTriggerHandler`, `OrderActivationQueueable`).
- Flow `Auto_Contract_Order_On_Activation` activo.
- Permission set `Error_Log_Access` asignado al usuario de QA.
- Producto **Monthly Named Users** con precio activo en el **Standard Price Book**, y Account **Burlington Textiles Corp of America** (ambos verificados el 30/09/2026).

### Pasos
1. *(Opcional, para diagnóstico)* Activar un debug log para el usuario de QA: *Setup → Debug Logs*.
2. Crear la Order y su producto **en la misma transacción**, con `SBQQ__PriceCalcStatus__c = 'Not Needed'`. Con el script del repo:
   ```bash
   sf apex run --file scripts/apex/qa-dev2-insert-path.apex --target-org smartbytes
   ```
   Anotar el Id de la Order que imprime el script (`QA-DEV2-01 Order creada: 801...`).
3. Esperar unos **30 segundos**.
4. Verificar los resultados.

### Resultados esperados

| # | Qué verificar | Dónde | Esperado |
|---|---|---|---|
| 1 | Status de la Order | Registro de la Order | **Activated** |
| 2 | Contracted | Registro de la Order | **true** (lo marca el Flow 2) |
| 3 | Job de nuestro Queueable | *Setup → Apex Jobs* | `OrderActivationQueueable`, **Completed**, 0 errores |
| 4 | Job de contracting | *Setup → Apex Jobs* | `QueueableContractOrdersClient`, **Completed** |
| 5 | Error "Too many queueable jobs" | Apex Jobs (columna Status Detail) y debug log | **No aparece** |
| 6 | Error Logs | Tab **Error Logs** | **Vacía** para esta Order |
| 7 | Contract / Subscription | Account → Contracts | **Observar y documentar.** La Order no viene de una Quote, así que CPQ puede no generar Subscription/Contract igual que en el flujo estándar. No es un criterio del DEV #2. |

Queries de apoyo (reemplazar `<ORDER_ID>`):
```bash
sf data query --target-org smartbytes --query "SELECT OrderNumber, Status, SBQQ__Contracted__c, SBQQ__PriceCalcStatus__c, ActivatedDate FROM Order WHERE Id = '<ORDER_ID>'"
sf data query --target-org smartbytes --query "SELECT ApexClass.Name, Status, NumberOfErrors, ExtendedStatus, CreatedDate FROM AsyncApexJob WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 10"
sf data query --target-org smartbytes --query "SELECT Name, Class_Name__c, Record_Id__c, Error_Message__c FROM Error_Log__c WHERE Record_Id__c = '<ORDER_ID>'"
```

### Si falla

| Síntoma | Causa probable | Siguiente paso |
|---|---|---|
| Order en Draft y no hay job de `OrderActivationQueueable` | CPQ pisó el `Not Needed` al insertar, o la Order no nació lista | Revisar el PriceCalcStatus actual y el debug log del insert |
| Order en Draft y un Error Log | Salesforce rechazó la activación | Leer `Error_Message__c` |
| `OrderActivationQueueable` en **Failed** con "Too many queueable jobs" | La activación dispara más de un enqueue dentro de nuestro job | Documentar y escalar al desarrollador: el camino del insert necesita otro diseño para este caso |
| Order Activated pero no Contracted | Flow 2 o validation de CPQ | Revisar el Flow `Auto_Contract_Order_On_Activation` |

### Limpieza
La Order de prueba queda en el org. Si se genera un Contract, dejarlo documentado junto con los Ids de la prueba en el Test Rail.

---

## QA-DEV1-01 — El vencimiento no se pisa en una Quote con productos y aprobación manual

**Requirement:** DEV #1, Parte A ("30 days from the date in which it was approved").
**Estado:** pendiente. Cubierto por tests unitarios y probado en el org con Quotes **sin Quote Lines** (Q-00061, Q-00072 a Q-00078).

### Por qué hace falta esta prueba
Salesforce no garantiza el orden entre nuestro `QuoteTrigger` y el trigger de CPQ `SBQQ.QuoteBefore`. Además, con Quote Lines, CPQ recalcula precios en un proceso asíncrono. Hay que confirmar que ninguno de los dos pisa la fecha que pone nuestro trigger al aprobar.

### Precondiciones
- `QuoteTrigger` y `QuoteTriggerHandler` deployados.
- `Quote_Approval_V2` activo. El usuario de QA cargado como **Approving Manager** de la Quote.

### Pasos
1. Crear una Opportunity abierta en *Burlington Textiles Corp of America* y una Quote con **Monthly Named Users**, **20% de descuento** y **Net 30**.
2. Esperar unos segundos a que CPQ calcule los precios. Anotar el **Expiration Date** (default de CPQ).
3. **Submit for Approval** → la Quote queda **In Review**, pendiente del Manager.
4. **Esperar al menos un día** (para que "hoy" sea distinto de la fecha de creación) y aprobarla desde *Items to Approve*.
5. Esperar 1 minuto y refrescar.

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | Status | **Approved** |
| 2 | Expiration Date | **Fecha de aprobación + 30** (no creación + 30) |
| 3 | Expiration Date después de 1 minuto (recálculo de CPQ) | **Sin cambios** |
| 4 | Error Logs | Vacía |

### Si falla
Si la fecha vuelve a creación + 30, CPQ la está pisando después de nuestro trigger. Documentar y escalar: habría que evaluar otro contexto (por ejemplo, after update) o un ajuste en la configuración de CPQ.

---

## QA-DEV1-02 — Recall automático por el job nocturno (sin forzar la fecha)

**Requirement:** DEV #1, Parte B ("the Quote approvals should be recalled").
**Estado:** pendiente. Cubierto por tests unitarios y probado en el org corriendo el Batch **a mano** (Q-00079). El job nocturno ya corrió solo el 01/10/2026 (Completed, 0 Quotes, 0 errores), pero todavía no procesó ninguna Quote real.

### Precondiciones
- Job **"Quote Expiration Recall - Nightly"** en estado WAITING (*Setup → Scheduled Jobs*).
- Una Quote **In Review** con aprobación pendiente, Opportunity abierta y **Expiration Date = mañana** (por ejemplo Net 60 + Submit).

### Pasos
1. Dejar la Quote preparada y no tocarla.
2. Al día siguiente, después de la 1:00 (America/Los_Angeles), revisar la Quote y los jobs.

### Resultados esperados

| # | Qué verificar | Dónde | Esperado |
|---|---|---|---|
| 1 | Status de la Quote | Registro de la Quote | **Draft**, sin candado |
| 2 | Approval History | Related list de la Quote | Paso **Recalled** con *"Recalled automatically: ..."* |
| 3 | Items to Approve del aprobador | Home del aprobador | La aprobación **ya no figura** |
| 4 | Job | *Setup → Apex Jobs* | `QuoteExpirationBatch`, **Completed**, 0 errores |
| 5 | Error Logs | Tab **Error Logs** | Vacía |

Query de apoyo:
```bash
sf data query --target-org smartbytes --query "SELECT ApexClass.Name, Status, JobItemsProcessed, NumberOfErrors, CreatedDate FROM AsyncApexJob WHERE ApexClass.Name = 'QuoteExpirationBatch' ORDER BY CreatedDate DESC LIMIT 5"
```

### Si falla

| Síntoma | Causa probable | Siguiente paso |
|---|---|---|
| No hay job de `QuoteExpirationBatch` esa noche | El job programado no está activo o el usuario que lo programó fue desactivado | Revisar *Scheduled Jobs* y reprogramarlo |
| Job Completed pero la Quote sigue In Review | No cumplía algún filtro (Opportunity ganada, sin Opportunity, no vencida) | Revisar los 4 filtros de `start` |
| Error Log "Recall failed" | El usuario del job no puede hacer recall de esa aprobación | Confirmar que el job lo programó un admin |

---

## QA-DEV4-01 — El contador se actualiza en vivo durante un Amendment de CPQ

**Requirement:** DEV #4 ("how many active Subscriptions are currently related to the Contract").
**Estado:** pendiente. Cubierto por tests unitarios (23) y por el backfill en el org. Los Amendments de prueba (Contract 00000108) se hicieron **antes** de deployar el trigger, así que falta ver `SubscriptionTrigger` corriendo **dentro** del contracting asíncrono de CPQ, junto con `SBQQ.SubscriptionAfter`.

### Precondiciones
- `SubscriptionTrigger`, `SubscriptionTriggerHandler` y `ActiveSubscriptionCounter` deployados.
- Permission set `Active_Subscriptions_Access` asignado al usuario de QA.
- Un Contract con **Monthly Named Users** cuya **fecha de inicio ya pasó** (para que la revisión sea vigente hoy).

### Pasos
1. Anotar *Active Subscriptions* del Contract (por ejemplo, 1).
2. **Amend** → en la Quote de Amendment dejar el **inicio = hoy** y subir la cantidad (por ejemplo, de 125 a 225) → Ordered.
   Por script (hace lo mismo que el botón Amend; completar `CONTRACT_NUMBER` y `NEW_QUANTITY` antes):
   ```bash
   sf apex run --file scripts/apex/qa-dev4-amendment.apex --target-org smartbytes
   ```
   Después ordenar la Quote con el comando que imprime el script.
3. Esperar unos 30 segundos (Order → DEV #2 → Flow 2 → contracting de CPQ) y refrescar el Contract.
4. Repetir con un Amendment que baje la cantidad (por ejemplo, de 225 a 215).

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | Subscription nueva | +100 (y después −10), con *Revised Subscription* = la original |
| 2 | *Active Subscriptions* | **Sin cambios** (sigue en 1: los Amendments no suman Subscriptions) |
| 3 | Job de contracting | `QueueableContractOrdersClient` **Completed** en *Setup → Apex Jobs* |
| 4 | Error Logs | Vacía |

### Si falla
| Síntoma | Causa probable | Siguiente paso |
|---|---|---|
| El número sube a 2 o 3 | La revisión no apunta a la original | Revisar `SBQQ__RevisedSubscription__c` de la Subscription nueva |
| El contracting falla | Algún límite dentro del job de CPQ | Revisar el debug log. Nuestro código usa 1 SOQL y 1 DML y no encola jobs |
| Error Log de `ActiveSubscriptionCounter` | Falló el update del Contract | Leer `Error_Message__c`. El Batch nocturno lo corrige |

---

## QA-DEV4-02 — Baja total de una Subscription por Amendment

**Requirement:** DEV #4, parte (B)/(C).
**Estado:** pendiente. Cubierto por `fullCancellationNotCountedTest`. En el org solo se probó una baja **parcial** (−10, SUB-0000013), que **no** completa `SBQQ__TerminatedDate__c`.

### Pasos
1. En un Contract de prueba (no el 00000108 de la demo), **Amend** con inicio = hoy y bajar la cantidad de una Subscription a **0** → Ordered. Se puede usar `scripts/apex/qa-dev4-amendment.apex` con `NEW_QUANTITY = 0`.
2. Esperar unos 30 segundos y refrescar.

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | Subscription nueva | Cantidad negativa por el total (por ejemplo, −125) apuntando a la original |
| 2 | `SBQQ__TerminatedDate__c` de la original | **Observar y documentar** (dato para el Code Review: ¿lo completa CPQ?) |
| 3 | *Active Subscriptions* | Baja en 1 (el neto es 0) |

---

## QA-DEV4-03 — El job nocturno corrige una Subscription que vence por fecha

**Requirement:** DEV #4, parte (C) "currently".
**Estado:** pendiente. Cubierto por `expiredByTimeTest`. El job *Active Subscriptions Recount - Nightly* está programado (02/10/2026) pero todavía no corrió.

### Pasos
1. Elegir una Subscription de prueba y poner **Subscription End Date = hoy** (sigue activa hoy, así que el número no cambia).
2. Al día siguiente, después de las 2:00 (America/Los_Angeles), refrescar el Contract.

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | *Active Subscriptions* | Bajó en 1, sin que nadie editara nada |
| 2 | Job | `ActiveSubscriptionRecountBatch` **Completed**, 0 errores, en *Setup → Apex Jobs* |
| 3 | Error Logs | Vacía |

---

## QA-DEV3-01 — Recepción del email de Renewal Quote y link

**Requirement:** DEV #3, Parte 3 ("the email should include a link to the Quote").
**Estado:** ✅ **CERRADO (05/10/2026, confirmado por Francisco).** Llegaron los emails de **Q-00092** y **Q-00108**, y sus links abren la Quote. Después del filtro de la Quote temporal de CPQ, la activación del Contract 00000111 **no** mandó email y el Batch mandó **uno solo** (Q-00108). El email de Q-00090 (link muerto, de la primera prueba) era la Quote temporal de CPQ: ver "Hallazgo" en [`code-review/DEV3.md`](code-review/DEV3.md), sección 2. Se conserva el detalle de abajo como guía para repetir la prueba.

### Pasos
1. Abrir el inbox del Owner de **Q-00092** (frandev → fpistone@firstchairservices.com). Revisar también Spam.
2. Buscar el asunto **"Renewal Quote created: Q-00092"**.
3. Hacer clic en el link.

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | Email recibido | Sí, con Quote, Account ("Burlington Textiles Corp of America") y Renewal Opportunity |
| 2 | Link | Abre Q-00092 en Lightning (después de loguearse) |
| 3 | Error Logs | Vacía |

### Si falla
| Síntoma | Causa probable | Siguiente paso |
|---|---|---|
| No llegó y no hay Error Log | Filtro de spam del dominio o Deliverability limitado | *Setup → Deliverability* (Access Level = All email) y *Setup → Email Log Files* |
| Error Log "Renewal Quote email failed" | Owner inactivo, Queue como Owner o Deliverability apagado | Leer `Error_Message__c` |

---

## QA-DEV3-02 — El job nocturno genera una Renewal Quote solo

**Requirement:** DEV #3, Parte 2 ("30 days before the end of a Contract").
**Estado:** pendiente. Cubierto por tests unitarios y probado en el org corriendo el Batch **a mano** (Contract 00000109 → Q-00092). El job *Renewal Quote Generation - Nightly* se programó el 05/10/2026 y todavía no corrió.

### Precondiciones
- Job *Renewal Quote Generation - Nightly* en WAITING (*Setup → Scheduled Jobs*).
- Un Contract **Activated**, con *Renewal Quoted* destildado y que venza dentro de los próximos 30 días. Se puede usar el **00000110** **después** de la demo (activándolo), o armar otro con `scripts/apex/dev3-1/2/3-*.apex`.

### Pasos
1. Dejar el Contract preparado y no tocarlo.
2. Al día siguiente, después de las 3:00 (America/Los_Angeles), revisar el Contract, la Renewal Opportunity y los jobs.

### Resultados esperados

| # | Qué verificar | Dónde | Esperado |
|---|---|---|---|
| 1 | *Renewal Quoted* | Contract | Tildado |
| 2 | Renewal Quote | Related list de la Opportunity | Type Renewal, Primary, con las cantidades del Contract |
| 3 | Etapa | Renewal Opportunity | Proposal/Price Quote |
| 4 | Jobs | *Setup → Apex Jobs* | `RenewalQuoteBatch` Completed, 0 errores; 1 `QueueableCalculatorService` Completed por Contract |
| 5 | Email | Inbox del Owner | Recibido (ver QA-DEV3-01) |
| 6 | Error Logs | Tab Error Logs | Vacía |

---

## QA-DEV3-03 — Activación desde la UI con un usuario Direct Sales

**Requirement:** DEV #3, Parte 1.
**Estado:** pendiente. En el org la activación se probó con frandev (System Administrator) por API.

### Pasos
1. Loguearse como **sh.dsales** (Direct Sales).
2. Abrir un Contract en Draft (con Subscriptions) → Edit → Status = Activated → Save.

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | Guardado | Sin errores. Si Salesforce dice que falta permiso, el perfil necesita "Activate Contracts" (es IC: consultarlo) |
| 2 | *Renewal Forecast* | Tildado |
| 3 | *Renewal Opportunity* | Con link, en Prospecting, con los productos del Contract |
| 4 | Error Logs | Vacía |

---

## QA-DEV3-04 — Amendment después de activar: ¿CPQ actualiza la Renewal Opportunity?

**Requirement:** DEV #3 + demo ("Contract Change Use Cases ... reflejados en la Renewal Opportunity").
**Estado:** pendiente (dato para el Code Review). En las pruebas los Amendments se hicieron **antes** de activar, y la Renewal Opportunity nació con 215. No se probó un Amendment **después** de que la Renewal Opportunity ya existe.

### Pasos
1. En un Contract activado con Renewal Opportunity (por ejemplo, 00000109), hacer un Amendment (+10) con `scripts/apex/dev3-3-amendment.apex` → Ordered.
2. Esperar ~30 s y revisar los productos de la Renewal Opportunity.

### Resultados esperados

| # | Qué verificar | Esperado |
|---|---|---|
| 1 | Subscription nueva | +10 apuntando a la original |
| 2 | Productos de la Renewal Opportunity | **Observar y documentar:** ¿pasa de 215 a 225? |
| 3 | Error Logs | Vacía |
