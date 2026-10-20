/**
 * @description Logic for QuoteTrigger. Solves Part A of DEV #1: when a Quote is approved,
 *              its expiration date becomes 30 days from the approval, overriding CPQ's
 *              default expiration (30 days from creation).
 *
 *              "Is approved" = the SBQQ__Status__c field changes to 'Approved'. It is set by the
 *              Set_Quote_Status_Approved field update of the Approval Processes, but a user or a
 *              data load can also change it: the trigger reacts to the FIELD CHANGE, no matter
 *              who makes it.
 *
 *              DEV #1 runs in before: we change a field on the same record, so setting it
 *              in memory is enough (no DML, no SOQL and no recursion).
 *
 *              It also solves Part 3 of DEV #3 (after insert): the email to the Owner of a
 *              new Renewal Quote.
 *
 *              Structure: the public methods (beforeInsert, beforeUpdate, afterInsert) are the
 *              entry point for each context and only call private static methods that hold the logic.
 *
 * Requirement DEV #1 (verbatim, first part): "Whenever a Quote record is approved, the
 * Quote Expiration Date should be set to 30 days from the date in which it was approved."
 * Requirement parts and where they are covered:
 *   (A) "whenever a Quote record is approved"   -> beforeUpdate (Status changes to Approved)
 *                                                 and beforeInsert (Quote created already approved)
 *   (B) "Quote Expiration Date ... 30 days from -> setExpirationDate
 *        the date in which it was approved"
 *
 * Requirement DEV #3 (verbatim, third part): "When this happens, the Owner of the Quote should
 * have an email notification sent to them indicating that a Renewal Quote has been created, and
 * the email should include a link to the Quote."
 * Requirement parts and where they are covered:
 *   (F) "a Renewal Quote has been created"         -> afterInsert, Quotes with SBQQ__Type__c = 'Renewal'
 *   (G) "the Owner of the Quote ... email ... link" -> sendRenewalQuoteNotifications
 */
public with sharing class QuoteTriggerHandler {

    public static final String STATUS_APPROVED = 'Approved';

    // Req (B): days of validity from the approval
    public static final Integer DAYS_UNTIL_EXPIRATION = 30;

    // Req (F): type CPQ uses when it creates Renewal Quotes (verified in the org, Q-00085)
    public static final String TYPE_RENEWAL = 'Renewal';

    private static final String CLASS_NAME = 'QuoteTriggerHandler';

    // ---------------------------------------------------------------------------------
    // Entry methods: one per trigger context. They only call the logic.
    // ---------------------------------------------------------------------------------

    /**
     * @description Before insert entry point. Req (A): the Quote is created already approved.
     * @param newQuoteList Trigger.new
     */
    public static void beforeInsert( List<SBQQ__Quote__c> newQuoteList ) {
        setExpirationDateOnInsert( newQuoteList );
    }

    /**
     * @description Before update entry point. Req (A): the Status changes to Approved.
     * @param newQuoteList    Trigger.new (the records with the new values)
     * @param oldQuoteByIdMap Trigger.oldMap (the records with the previous values)
     */
    public static void beforeUpdate( List<SBQQ__Quote__c> newQuoteList, Map<Id, SBQQ__Quote__c> oldQuoteByIdMap ) {
        setExpirationDateOnUpdate( newQuoteList, oldQuoteByIdMap );
    }

    /**
     * @description After insert entry point. Req (F): a Renewal Quote is created. In after
     *              because the email link needs the Quote Id.
     * @param newQuoteList Trigger.new
     */
    public static void afterInsert( List<SBQQ__Quote__c> newQuoteList ) {
        sendRenewalQuoteNotifications( newQuoteList );
    }

    // ---------------------------------------------------------------------------------
    // Logic (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Req (A). On insert there is no previous value: it is enough that the Quote
     *              is created with Status = Approved.
     * @param newQuoteList Trigger.new
     */
    private static void setExpirationDateOnInsert( List<SBQQ__Quote__c> newQuoteList ) {
        List<SBQQ__Quote__c> approvedQuoteList = new List<SBQQ__Quote__c>();
        for ( SBQQ__Quote__c newQuote : newQuoteList ) {
            if ( newQuote.SBQQ__Status__c == STATUS_APPROVED ) {
                approvedQuoteList.add( newQuote );
            }
        }
        setExpirationDate( approvedQuoteList );
    }

    /**
     * @description Req (A). Only processes the Quotes whose Status CHANGED to Approved.
     *              If the Quote was already approved and another field is edited, the
     *              expiration is not recalculated (the approval date did not change).
     * @param newQuoteList    Trigger.new
     * @param oldQuoteByIdMap Trigger.oldMap
     */
    private static void setExpirationDateOnUpdate( List<SBQQ__Quote__c> newQuoteList, Map<Id, SBQQ__Quote__c> oldQuoteByIdMap ) {
        List<SBQQ__Quote__c> approvedQuoteList = new List<SBQQ__Quote__c>();
        for ( SBQQ__Quote__c newQuote : newQuoteList ) {
            SBQQ__Quote__c oldQuote = oldQuoteByIdMap.get( newQuote.Id );
            // "Is approved" means the value CHANGED to Approved in this transaction
            Boolean statusChanged = newQuote.SBQQ__Status__c != oldQuote.SBQQ__Status__c;
            if ( statusChanged && newQuote.SBQQ__Status__c == STATUS_APPROVED ) {
                approvedQuoteList.add( newQuote );
            }
        }
        setExpirationDate( approvedQuoteList );
    }

    /**
     * @description Req (B). The rule in a single place: expiration = today + 30 days.
     *              "Today" is the approval date, because this code runs in the same
     *              transaction that approves the Quote. The date is calculated only once,
     *              outside the loop. We are in before: no DML is needed.
     * @param approvedQuoteList Quotes that were just approved
     */
    private static void setExpirationDate( List<SBQQ__Quote__c> approvedQuoteList ) {
        if ( approvedQuoteList.isEmpty() ) {
            return;
        }
        Date expirationDate = Date.today().addDays( DAYS_UNTIL_EXPIRATION );
        for ( SBQQ__Quote__c approvedQuote : approvedQuoteList ) {
            approvedQuote.SBQQ__ExpirationDate__c = expirationDate;
        }
    }

    /**
     * @description Req (F) and (G). Sends an email to the Owner of each new Renewal Quote, with a
     *              link to the Quote. It notifies for every REQUESTED Renewal Quote (Contract with
     *              SBQQ__RenewalQuoted__c = true), whether DEV #3's Batch or a user requested it
     *              (confirmed assumption). It does not notify for the temporary Renewal Quote that
     *              CPQ creates and deletes when the Contract is activated.
     *
     *              - Recipient: setTargetObjectId( OwnerId ). Emails to internal users do not
     *                count against the org's daily email limit (15 in Developer Edition).
     *              - A single Messaging.sendEmail for all the Quotes (never inside the loop:
     *                the limit is 10 sends per transaction).
     *              - try/catch: this code runs INSIDE the save in which CPQ creates the Quote.
     *                An uncaught exception would roll back the Renewal Quote. The error is stored
     *                in Error_Log__c (it does not fail silently).
     * @param newQuoteList Trigger.new
     */
    private static void sendRenewalQuoteNotifications( List<SBQQ__Quote__c> newQuoteList ) {
        Set<Id> renewalQuoteIdSet = new Set<Id>();
        for ( SBQQ__Quote__c newQuote : newQuoteList ) {
            if ( newQuote.SBQQ__Type__c == TYPE_RENEWAL ) {
                renewalQuoteIdSet.add( newQuote.Id );
            }
        }
        // Condition before the SOQL: most Quotes are not Renewals
        if ( renewalQuoteIdSet.isEmpty() ) {
            return;
        }

        // The link opens the record in Lightning: https://<org domain>/<Quote Id>
        String orgUrl = URL.getOrgDomainUrl().toExternalForm();

        // Query to get the Account and Opportunity names and the flag of the Contract being
        // renewed (Quote -> Opportunity -> Contract). None of that comes in Trigger.new.
        List<SBQQ__Quote__c> quoteList = [
            SELECT Id, Name, OwnerId, SBQQ__Account__r.Name, SBQQ__Opportunity2__r.Name,
                SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c
            FROM SBQQ__Quote__c
            WHERE Id IN :renewalQuoteIdSet
        ];

        // Only notify for the Renewal Quotes that someone REQUESTED (the Batch or a user checked
        // SBQQ__RenewalQuoted__c on the Contract). When a Contract is activated, CPQ creates a
        // TEMPORARY Renewal Quote to calculate the Renewal Opportunity prices and deletes it seconds
        // later (verified in the org, Q-00083 and Q-00090). At that moment the flag is false.
        // It is compared with == true because if the Opportunity has no Contract the value is null.
        List<SBQQ__Quote__c> renewalQuoteList = new List<SBQQ__Quote__c>();
        for ( SBQQ__Quote__c quote : quoteList ) {
            if ( quote.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c == true ) {
                renewalQuoteList.add( quote );
            }
        }
        if ( renewalQuoteList.isEmpty() ) {
            return;
        }

        List<Messaging.SingleEmailMessage> emailList = new List<Messaging.SingleEmailMessage>();
        for ( SBQQ__Quote__c renewalQuote : renewalQuoteList ) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId( renewalQuote.OwnerId );
            // With a User as recipient, Salesforce requires not saving it as an Activity
            email.setSaveAsActivity( false );
            email.setSubject( 'Renewal Quote created: ' + renewalQuote.Name );
            email.setPlainTextBody( buildEmailBody( renewalQuote, orgUrl ) );
            emailList.add( email );
        }

        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        try {
            List<Messaging.SendEmailResult> resultList = Messaging.sendEmail( emailList, false );
            // The results come back in the same order as the emails: they are read by position
            for ( Integer i = 0; i < resultList.size(); i++ ) {
                if ( !resultList[i].isSuccess() ) {
                    errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, renewalQuoteList[i].Id,
                        'Renewal Quote email failed: ' + resultList[i].getErrors()[0].getMessage() ) );
                }
            }
        } catch ( Exception e ) {
            // For example, if the org has email sending turned off (Deliverability)
            for ( SBQQ__Quote__c renewalQuote : renewalQuoteList ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, renewalQuote.Id,
                    'Renewal Quote email failed: ' + e.getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }

    /**
     * @description Req (G). Builds the email text: what was created, for which Account, and the link.
     * @param renewalQuote Renewal Quote (with Account and Opportunity queried)
     * @param orgUrl       Org domain, for example https://firstchair-dev-ed.develop.my.salesforce.com
     * @return Email body in plain text
     */
    private static String buildEmailBody( SBQQ__Quote__c renewalQuote, String orgUrl ) {
        String body = 'Hello,\n\n'
            + 'A Renewal Quote has been created and you are its Owner. '
            + 'Your team can start preparing for the renewal sale.\n\n'
            + 'Quote: ' + renewalQuote.Name + '\n'
            + 'Account: ' + renewalQuote.SBQQ__Account__r.Name + '\n'
            + 'Renewal Opportunity: ' + renewalQuote.SBQQ__Opportunity2__r.Name + '\n\n'
            + 'Open the Quote: ' + orgUrl + '/' + renewalQuote.Id + '\n\n'
            + 'This is an automatic notification from Salesforce.';
        return body;
    }
}
