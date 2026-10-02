// QA-DEV4-01 / QA-DEV4-02 (ver docs/qa-pending.md)
// Crea un Amendment de CPQ sobre un Contract (lo mismo que el botón "Amend") y le cambia la
// cantidad a la primera línea, con inicio HOY para que la revisión sea vigente hoy.
// Después hay que esperar unos segundos a que CPQ recalcule y marcar la Quote como Ordered
// (desde la UI o con el comando que imprime el script).
// Antes de ejecutar: completar CONTRACT_NUMBER y NEW_QUANTITY.
//   - QA-DEV4-01: NEW_QUANTITY mayor o menor que la actual (ej. 225 o 215)
//   - QA-DEV4-02: NEW_QUANTITY = 0 (baja total). NO usar el Contract 00000108 (es el de la demo)
// Ejecutar con:
//   sf apex run --file scripts/apex/qa-dev4-amendment.apex --target-org smartbytes

String CONTRACT_NUMBER = '00000000';
Decimal NEW_QUANTITY = 225;

Contract con = [SELECT Id, Active_Subscriptions__c FROM Contract WHERE ContractNumber = :CONTRACT_NUMBER LIMIT 1];
System.debug( 'QA-DEV4 Active Subscriptions ANTES: ' + con.Active_Subscriptions__c );

// API pública de CPQ: crea la Opportunity + Quote de Amendment y devuelve la Quote en JSON
String quoteJson = SBQQ.ServiceRouter.load( 'SBQQ.ContractManipulationAPI.ContractAmender', con.Id, null );
Map<String, Object> quoteModel = (Map<String, Object>) JSON.deserializeUntyped( quoteJson );
Map<String, Object> quoteRecord = (Map<String, Object>) quoteModel.get( 'record' );
Id quoteId = (Id) quoteRecord.get( 'Id' );

// Inicio del Amendment = hoy, para que la revisión cuente desde hoy
update new SBQQ__Quote__c( Id = quoteId, SBQQ__StartDate__c = Date.today() );

// La línea trae la cantidad TOTAL actual: se pone la cantidad final y CPQ calcula la diferencia
SBQQ__QuoteLine__c line = [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quoteId LIMIT 1];
System.debug( 'QA-DEV4 Cantidad actual de la línea: ' + line.SBQQ__Quantity__c + ' -> nueva: ' + NEW_QUANTITY );
line.SBQQ__Quantity__c = NEW_QUANTITY;
update line;

System.debug( 'QA-DEV4 Quote de Amendment: ' + quoteId );
System.debug( 'QA-DEV4 Esperar ~20 s y ordenar con: sf data update record --sobject SBQQ__Quote__c --record-id ' + quoteId + ' --values "SBQQ__Ordered__c=true" --target-org smartbytes' );
