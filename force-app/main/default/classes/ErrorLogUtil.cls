/**
 * @description Utility class to record errors in the Error_Log__c object.
 *              It is used in two steps: first each log is built with buildLog (inside the loop,
 *              no DML) and at the end all of them are saved together with saveLogs (one insert).
 */
public with sharing class ErrorLogUtil {

    /**
     * @description Builds an Error_Log__c record in memory. It does not save it.
     * @param className    Apex class where the error happened
     * @param recordId     Id of the record that failed (can be null)
     * @param errorMessage Error message
     * @return The log, ready to be saved
     */
    public static Error_Log__c buildLog( String className, Id recordId, String errorMessage ) {
        Error_Log__c errorLog = new Error_Log__c();
        errorLog.Class_Name__c = className;
        errorLog.Record_Id__c = recordId;
        errorLog.Error_Message__c = errorMessage;
        return errorLog;
    }

    /**
     * @description Saves all the logs with a single insert (never inside a loop).
     *              Uses SYSTEM_MODE: the log is a system record, not a user record, so it has to
     *              be saved even if the user who started the process has no permissions on
     *              Error_Log__c. If it failed, it would cancel the very process we wanted to protect.
     *              Who can SEE the logs is still controlled by the Error_Log_Access permission set.
     * @param errorLogList Logs to save
     */
    public static void saveLogs( List<Error_Log__c> errorLogList ) {
        if ( errorLogList.isEmpty() ) {
            return;
        }
        Database.insert( errorLogList, AccessLevel.SYSTEM_MODE );
    }
}
