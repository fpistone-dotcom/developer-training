/**
 * @description Tests de ErrorLogUtil: armar logs y guardarlos con un solo insert.
 */
@IsTest
private class ErrorLogUtilTest {

    /**
     * @description Positivo: los logs armados con buildLog se guardan con sus datos.
     */
    @isTest
    static void saveLogsTest() {
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        errorLogList.add( ErrorLogUtil.buildLog( 'SomeClass', null, 'First error' ) );
        errorLogList.add( ErrorLogUtil.buildLog( 'SomeClass', null, 'Second error' ) );

        Test.startTest();
        ErrorLogUtil.saveLogs( errorLogList );
        Test.stopTest();

        // WITH SYSTEM_MODE: el test verifica el log sin depender de los permisos del usuario que corre el test
        List<Error_Log__c> savedLogList = [
            SELECT Class_Name__c, Error_Message__c
            FROM Error_Log__c
            WITH SYSTEM_MODE
        ];
        System.assertEquals( 2, savedLogList.size(), 'Deberían guardarse los 2 logs' );

        // Los campos Long Text no se pueden ordenar en SOQL, así que juntamos los mensajes en un Set
        Set<String> savedMessageSet = new Set<String>();
        for ( Error_Log__c savedLog : savedLogList ) {
            System.assertEquals( 'SomeClass', savedLog.Class_Name__c, 'El log debería guardar el nombre de la clase' );
            savedMessageSet.add( savedLog.Error_Message__c );
        }
        System.assert( savedMessageSet.contains( 'First error' ), 'Debería guardarse el primer mensaje' );
        System.assert( savedMessageSet.contains( 'Second error' ), 'Debería guardarse el segundo mensaje' );
    }

    /**
     * @description Negativo: con una lista vacía no se hace ningún insert ni falla.
     */
    @isTest
    static void saveLogsEmptyListTest() {
        Test.startTest();
        ErrorLogUtil.saveLogs( new List<Error_Log__c>() );
        Test.stopTest();

        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'Con una lista vacía no debería guardarse nada' );
    }
}
