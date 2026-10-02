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
