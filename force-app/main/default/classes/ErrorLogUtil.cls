/**
 * @description Clase utilitaria para registrar errores en el objeto Error_Log__c.
 *              Se usa en dos pasos: primero se arma cada log con buildLog (dentro del loop,
 *              sin DML) y al final se guardan todos juntos con saveLogs (un solo insert).
 */
public with sharing class ErrorLogUtil {

    /**
     * @description Arma un registro de Error_Log__c en memoria. No lo guarda.
     * @param className    Clase de Apex donde ocurrió el error
     * @param recordId     Id del registro que falló (puede ser null)
     * @param errorMessage Mensaje del error
     * @return El log listo para guardar
     */
    public static Error_Log__c buildLog( String className, Id recordId, String errorMessage ) {
        Error_Log__c errorLog = new Error_Log__c();
        errorLog.Class_Name__c = className;
        errorLog.Record_Id__c = recordId;
        errorLog.Error_Message__c = errorMessage;
        return errorLog;
    }

    /**
     * @description Guarda todos los logs con un solo insert (nunca dentro de un loop).
     *              Usa SYSTEM_MODE: el log es un registro del sistema, no del usuario, así que
     *              tiene que guardarse aunque el usuario que disparó el proceso no tenga permisos
     *              sobre Error_Log__c. Si fallara, cancelaría el proceso que queríamos proteger.
     *              Quién puede VER los logs lo sigue controlando el permission set Error_Log_Access.
     * @param errorLogList Logs a guardar
     */
    public static void saveLogs( List<Error_Log__c> errorLogList ) {
        if ( errorLogList.isEmpty() ) {
            return;
        }
        Database.insert( errorLogList, AccessLevel.SYSTEM_MODE );
    }
}
