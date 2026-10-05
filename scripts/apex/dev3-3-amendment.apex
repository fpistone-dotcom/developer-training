// DEV #3 - Preparación de datos, paso 3 de 3 (ver docs/code-review/DEV3.md, sección 8)
// Crea un Amendment de CPQ (lo mismo que el botón "Amend") con la fecha de inicio y la cantidad
// FINAL indicadas. Se corre dos veces: +100 en el mes 6 (125 -> 225) y -10 en el mes 9 (225 -> 215).
// Después hay que esperar ~20 s a que CPQ recalcule y marcar la Quote como Ordered con el
// comando que imprime el script. La Order de Amendment se activa sola (DEV #2) y el Flow 2 la contrata.
// Antes de ejecutar: completar CONTRACT_NUMBER, START_DATE y NEW_QUANTITY.
// Ejecutar con:
//   sf apex run --file scripts/apex/dev3-3-amendment.apex --target-org smartbytes

String CONTRACT_NUMBER = '00000000';
Date START_DATE = Date.newInstance( 2026, 5, 1 );
Decimal NEW_QUANTITY = 225;

Contract con = [SELECT Id FROM Contract WHERE ContractNumber = :CONTRACT_NUMBER LIMIT 1];

// API pública de CPQ: crea la Opportunity + Quote de Amendment y devuelve la Quote en JSON
String quoteJson = SBQQ.ServiceRouter.load( 'SBQQ.ContractManipulationAPI.ContractAmender', con.Id, null );
Map<String, Object> quoteModel = (Map<String, Object>) JSON.deserializeUntyped( quoteJson );
Map<String, Object> quoteRecord = (Map<String, Object>) quoteModel.get( 'record' );
Id quoteId = (Id) quoteRecord.get( 'Id' );

update new SBQQ__Quote__c( Id = quoteId, SBQQ__StartDate__c = START_DATE );

// La línea trae la cantidad TOTAL actual: se pone la cantidad final y CPQ calcula la diferencia
SBQQ__QuoteLine__c line = [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quoteId LIMIT 1];
System.debug( 'DEV3 Cantidad actual: ' + line.SBQQ__Quantity__c + ' -> nueva: ' + NEW_QUANTITY );
line.SBQQ__Quantity__c = NEW_QUANTITY;
update line;

System.debug( 'DEV3 Quote de Amendment: ' + quoteId );
System.debug( 'DEV3 Esperar ~20 s y ordenar con: sf data update record --sobject SBQQ__Quote__c --record-id ' + quoteId + ' --values "SBQQ__Ordered__c=true" --target-org smartbytes' );
