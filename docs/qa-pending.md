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
