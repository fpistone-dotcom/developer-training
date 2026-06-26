public with sharing class QuoteTriggerHandler {

    // --- PUBLIC ROUTING METHODS ---

    public static void beforeInsert(List<Quote__c> newList) {
        // REQUIREMENT 2.6.1: Watermark
        handleWatermarks(newList, null);

        // REQUIREMENT 2.6.2 (Insert): Ship To and address handling
        handleShipToAndAddresses(newList, null);

        // REQUIREMENT 2.6.4: Apply automatic discounts on new Quote
        applyAutoDiscounts(newList, null);
    }

    public static void beforeUpdate(List<Quote__c> newList, Map<Id, Quote__c> oldMap) {
        // REQUIREMENT 2.6.1: Watermark
        handleWatermarks(newList, oldMap);
        
        // REQUIREMENT 2.6.2 (Update): Ship To and address handling
        handleShipToAndAddresses(newList, oldMap);

        // REQUIREMENT 2.6.4: Recalculate discounts if Opportunity changes (pushed from Opportunity)
        applyAutoDiscounts(newList, oldMap);
    }

    public static void afterInsert(List<Quote__c> newList) {
        // REQUIREMENT 2.6.3: Recalculate Opportunity count
        countApprovedQuotes(newList, null);
    }

    public static void afterUpdate(List<Quote__c> newList, Map<Id, Quote__c> oldMap) {
        // REQUIREMENT 2.6.3: Recalculate count when status or Opportunity changes
        countApprovedQuotes(newList, oldMap);
    }

    public static void afterDelete(Map<Id, Quote__c> oldMap) {
        // REQUIREMENT 2.6.3: Pass null for newList because records were deleted
        countApprovedQuotes(null, oldMap);
    }

    public static void afterUndelete(List<Quote__c> newList) {
        // REQUIREMENT 2.6.3: Recalculate when restored from recycle bin
        countApprovedQuotes(newList, null);
    }


    // --- PRIVATE LOGIC METHODS ---

    // Requirement 2.6.1: Control watermark based on Quote status
    private static void handleWatermarks(List<Quote__c> newList, Map<Id, Quote__c> oldMap) {
        for (Quote__c q : newList) {
            // Evaluate if the record is new or if the Status field changed
            if (oldMap == null || q.Status__c != oldMap.get(q.Id).Status__c) {
                // COMENTADO: Watermark_Shown__c no existe en la Org
                if (q.Status__c != 'Approved') {
                    // q.Watermark_Shown__c = true;
                } else {
                    // q.Watermark_Shown__c = false;
                }
            }
        }
    }

    // Requirement 2.6.2:
    // Manage Ship To and address assignment/update for insert and edit.
    private static void handleShipToAndAddresses(List<Quote__c> newList, Map<Id, Quote__c> oldMap) {
        Set<Id> oppIds = new Set<Id>();
        Set<Id> accIds = new Set<Id>();
        List<Quote__c> quotesToProcess = new List<Quote__c>();

        for (Quote__c q : newList) {
            // Condition for insert
            Boolean isNewRecord = (oldMap == null);
            
            // Condition for update
            Boolean requiresUpdate = (oldMap != null && 
                (q.Status__c == 'Draft' || 
                q.Opportunity__c != oldMap.get(q.Id).Opportunity__c || 
                q.Account__c != oldMap.get(q.Id).Account__c)
            );

            if (isNewRecord || requiresUpdate) {
                quotesToProcess.add(q);
                if (q.Opportunity__c != null) oppIds.add(q.Opportunity__c);
                if (q.Account__c != null) accIds.add(q.Account__c);
            }
        }

        // If no Quote meets the criteria, exit early
        if (quotesToProcess.isEmpty()) return;

        // Bulk SOQL: fetch parent Opportunity and Account values
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, Ship_To_Override__c FROM Opportunity WHERE Id IN :oppIds
        ]);
        
        // CORREGIDO: Se removió Ship_To__c de la query de Account porque no existe
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id FROM Account WHERE Id IN :accIds
        ]);

        Set<Id> contactIdsToQuery = new Set<Id>();

        // Part 1 and 4: Apply precedence
        for (Quote__c q : quotesToProcess) {
            Id chosenContactId = null;

            // Priority A: Opportunity
            if (q.Opportunity__c != null && oppMap.containsKey(q.Opportunity__c)) {
                chosenContactId = oppMap.get(q.Opportunity__c).Ship_To_Override__c;
            }

            // Priority B: Account (COMENTADO: Ship_To__c no existe en Account)
            /*
            if (chosenContactId == null && q.Account__c != null && accMap.containsKey(q.Account__c)) {
                chosenContactId = accMap.get(q.Account__c).Ship_To__c;
            }
            */

            // Part 2: Handle alert when no Ship To is available
            if (chosenContactId != null) {
                q.Ship_To__c = chosenContactId;
                q.Ship_To_Approval_Required__c = false; 
                contactIdsToQuery.add(chosenContactId);
            } else {
                q.Ship_To__c = null; 
                q.Ship_To_Approval_Required__c = true;
            }
        }

        // Bulk SOQL: fetch contact addresses
        Map<Id, Contact> contactMap = new Map<Id, Contact>();
        if (!contactIdsToQuery.isEmpty()) {
            contactMap = new Map<Id, Contact>([
                SELECT Id, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry 
                FROM Contact 
                WHERE Id IN :contactIdsToQuery
            ]);
        }

        // Part 3 and 4: Stamp or refresh addresses on processed Quotes
        // COMENTADO: Los campos personalizados de dirección (Shipping_Street__c, etc.) no existen en Quote__c
        for (Quote__c q : quotesToProcess) {
            if (q.Ship_To__c != null && contactMap.containsKey(q.Ship_To__c)) {
                Contact c = contactMap.get(q.Ship_To__c);
                /*
                q.Shipping_Street__c = c.MailingStreet;
                q.Shipping_City__c = c.MailingCity;
                q.Shipping_State__c = c.MailingState;
                q.Shipping_Postal_Code__c = c.MailingPostalCode;
                q.Shipping_Country__c = c.MailingCountry;
                */
            } else if (q.Ship_To__c == null) {
                /*
                q.Shipping_Street__c = null;
                q.Shipping_City__c = null;
                q.Shipping_State__c = null;
                q.Shipping_Postal_Code__c = null;
                q.Shipping_Country__c = null;
                */
            }
        }
    }

    // Requirement 2.6.3:
    // Count approved Quotes per Opportunity and update the manual roll-up summary.
    private static void countApprovedQuotes(List<Quote__c> newList, Map<Id, Quote__c> oldMap) {
        Set<Id> oppIdsToRecalculate = new Set<Id>();

        // Scenario A: Insert, Update or Undelete (newList has data)
        if (newList != null) {
            for (Quote__c q : newList) {
                Quote__c oldQ = (oldMap != null) ? oldMap.get(q.Id) : null;
                
                if (oldQ == null) {
                    if (q.Status__c == 'Approved' && q.Opportunity__c != null) {
                        oppIdsToRecalculate.add(q.Opportunity__c);
                    }
                } else {
                    if (q.Status__c != oldQ.Status__c || q.Opportunity__c != oldQ.Opportunity__c) {
                        if (q.Status__c == 'Approved' && q.Opportunity__c != null) {
                            oppIdsToRecalculate.add(q.Opportunity__c);
                        }
                        if (oldQ.Status__c == 'Approved' && oldQ.Opportunity__c != null) {
                            oppIdsToRecalculate.add(oldQ.Opportunity__c);
                        }
                    }
                }
            }
        } 
        // Scenario B: Delete (newList is null, only oldMap available)
        else if (oldMap != null) {
            for (Quote__c oldQ : oldMap.values()) {
                if (oldQ.Status__c == 'Approved' && oldQ.Opportunity__c != null) {
                    oppIdsToRecalculate.add(oldQ.Opportunity__c);
                }
            }
        }

        // If no Opportunity was affected, exit early
        if (oppIdsToRecalculate.isEmpty()) return;

        // COMENTADO: Number_Of_Approved_Quote__c no existe en Opportunity
        /*
        Map<Id, Opportunity> oppsToUpdate = new Map<Id, Opportunity>();
        for (Id oppId : oppIdsToRecalculate) {
            oppsToUpdate.put(oppId, new Opportunity(
                Id = oppId, 
                Number_Of_Approved_Quote__c = 0
            ));
        }

        for (AggregateResult ar : [
            SELECT Opportunity__c oppId, COUNT(Id) total
            FROM Quote__c
            WHERE Opportunity__c IN :oppIdsToRecalculate 
            AND Status__c = 'Approved'
            GROUP BY Opportunity__c
        ]) {
            Id oId = (Id)ar.get('oppId');
            Integer totalQuotes = (Integer)ar.get('total');
            
            oppsToUpdate.get(oId).Number_Of_Approved_Quote__c = totalQuotes;
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate.values();
        }
        */
    }

    // Requirement 2.6.4: Automatic Discount Matrix.
    // Evaluate Opportunity Type and Priority to assign the correct Quote discount.
    private static void applyAutoDiscounts(List<Quote__c> newList, Map<Id, Quote__c> oldMap) {
        Set<Id> oppIds = new Set<Id>();
        List<Quote__c> draftQuotes = new List<Quote__c>();

        // Step 1: Filter only Draft Quotes with a linked Opportunity
        for (Quote__c q : newList) {
            if (q.Status__c == 'Draft' && q.Opportunity__c != null) {
                draftQuotes.add(q);
                oppIds.add(q.Opportunity__c);
            }
        }

        if (draftQuotes.isEmpty()) return;

        // Step 2: SOQL to get Customer_Type__c and Priority__c from parent Opportunities
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, Customer_Type__c, Priority__c 
            FROM Opportunity 
            WHERE Id IN :oppIds
        ]);

        // Step 3: CORREGIDO - Se utiliza el campo real Discount__c en lugar de los campos SBQQ__ de CPQ
        for (Quote__c q : draftQuotes) {
            if (oppMap.containsKey(q.Opportunity__c)) {
                Opportunity parentOpp = oppMap.get(q.Opportunity__c);
                String custType = parentOpp.Customer_Type__c;
                String priority = parentOpp.Priority__c;

                q.Discount__c = null;

                if (custType == 'End Customer') {
                    if (priority == 'Low') q.Discount__c = 0;
                    else if (priority == 'Medium') q.Discount__c = 10;
                    else if (priority == 'High') q.Discount__c = 20;
                } 
                else if (custType == 'Partner') {
                    if (priority == 'Low') q.Discount__c = 0;
                    else if (priority == 'Medium') q.Discount__c = 15;
                    else if (priority == 'High') q.Discount__c = 25;
                } 
                else if (custType == 'Distributor') {
                    if (priority == 'Low') q.Discount__c = 5;
                    else if (priority == 'Medium') q.Discount__c = 10;
                    else if (priority == 'High') q.Discount__c = 25;
                }
            }
        }
    }
}