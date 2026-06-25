public class AccountTriggerHandler {

    /*************** Routing Methods ***************/

    public static void afterUpdate(List<Account> newList, Map<Id, Account> oldMap) {
        updateRelatedOpportunities(newList, oldMap);

        pushShipToChangesToQuotes(newList, oldMap);
    }

    /*************** Helper Methods ***************/

    private static void updateRelatedOpportunities(List<Account> newList, Map<Id, Account> oldMap){

        Set<Id> updatedAccountIds = new Set<Id>();
        List<Opportunity> oppsToUpdate  = new List<Opportunity>();
        
        for (Account acc : newList) {
            // Add Account to Set if the Type field has changed
            if (acc.Type != oldMap.get(acc.Id).Type) {
                updatedAccountIds.add(acc.Id);
            }
        }
        
        // Only proceed if there are Accounts that have had the Type field change
        if (!updatedAccountIds.isEmpty()) {
            
            // Get Accounts and child Opportunities that are not Closed
            Map<Id, Account> updatedAccountMap = new Map<Id, Account>([
                SELECT Id, Type,
                    (
                        SELECT Id, Type
                        FROM Opportunities
                        WHERE StageName != 'Closed Won' 
                        AND StageName != 'Closed Lost'
                    )
                FROM Account
                WHERE Id IN :updatedAccountIds
            ]);
        
            // Loop through updated Account records
            for (Account acc : updatedAccountMap.values()) {
                
                // Loop through child Opportunity records
                for (Opportunity opp : acc.Opportunities) {
        
                    // If the Account has been updated to Prospect, ensure the Opp is "New Customer"
                    if (acc.Type == 'Prospect' && opp.Type != 'New Customer') {
                        opp.Type = 'New Customer';
                        oppsToUpdate.add(opp);
        
                    // Otherwise, if the Opp isn't already "Existing Customer.." update it
                    } else if (opp.Type != 'Existing Customer - Upgrade') {
                        opp.Type = 'Existing Customer - Upgrade';
                        oppsToUpdate.add(opp);
                    }
                    
                }
                
            }
        
            update oppsToUpdate;

        }

    }

    // Requirement 2.6.2 (Part 4):
    // If the Account Ship To changes, push updates to child Quotes in Draft.

    private static void pushShipToChangesToQuotes(List<Account> newList, Map<Id, Account> oldMap) {
        Set<Id> changedAccIds = new Set<Id>();

        // Step 1: Filter only Accounts where the field changed
        for (Account acc : newList) {
            if (acc.Ship_To__c != oldMap.get(acc.Id).Ship_To__c) {
                changedAccIds.add(acc.Id);
            }
        }

        if (changedAccIds.isEmpty()) return;

        // Step 2: Query all child Quotes for those Accounts in Draft
        List<Quote__c> childQuotesToUpdate = [
            SELECT Id 
            FROM Quote__c 
            WHERE Account__c IN :changedAccIds 
            AND Status__c = 'Draft'
        ];

        // Step 3: Perform bulk DML
        if (!childQuotesToUpdate.isEmpty()) {
            update childQuotesToUpdate;
        }
    }
}