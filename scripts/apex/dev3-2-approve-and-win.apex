// DEV #3 - Preparación de datos, paso 2 de 3 (ver docs/code-review/DEV3.md, sección 8)
// Manda la Quote a aprobación (Auto_Approval la aprueba sola) y pasa la Opportunity a Closed Won.
// Eso arranca la cadena del Req #31: Flow 1 (Quote Ordered) -> Order -> DEV #2 (Activated) ->
// Flow 2 (Contracted) -> CPQ crea el Contract en Draft. Esperar ~30 s antes del paso 3.
// Antes de ejecutar: completar OPPORTUNITY_NAME (el mismo del paso 1).
// Ejecutar con:
//   sf apex run --file scripts/apex/dev3-2-approve-and-win.apex --target-org smartbytes

String OPPORTUNITY_NAME = 'DEV3 E2E Test - Renewal';

Opportunity opp = [SELECT Id, SBQQ__PrimaryQuote__c FROM Opportunity WHERE Name = :OPPORTUNITY_NAME LIMIT 1];

Approval.ProcessSubmitRequest submitRequest = new Approval.ProcessSubmitRequest();
submitRequest.setObjectId( opp.SBQQ__PrimaryQuote__c );
submitRequest.setComments( 'DEV3 test data' );
Approval.ProcessResult result = Approval.process( submitRequest );
System.debug( 'DEV3 Approval: ' + result.getInstanceStatus() );

opp.StageName = 'Closed Won';
update opp;
System.debug( 'DEV3 Opportunity Closed Won: ' + opp.Id );
