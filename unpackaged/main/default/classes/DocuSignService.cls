public with sharing class DocuSignService {
    @AuraEnabled
    public static String createEnvelopeAndGetEmbeddedSendingUrl(Id opportunityId) {
        Opportunity opp = [
            SELECT Name, Contact_B2C__c, Contact_B2C__r.Email, Contact_B2C__r.Name
            FROM Opportunity
            WHERE Id = :opportunityId LIMIT 1
        ];
    
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign_eSign/restapi/v2.1/accounts/30667966/envelopes');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
    
        // Initialize the JSON body for creating the envelope
        Map<String, Object> envelopeBody = new Map<String, Object>{
            'status' => 'created',
            'emailSubject' => 'Please sign the document for Opportunity: ' + opp.Name
        };
    
        // Add recipient details only if both Contact_B2C__c and Contact_B2C__r.Email are not null
        if (opp.Contact_B2C__c != null && String.isNotBlank(opp.Contact_B2C__r.Email)) {
            Map<String, Object> recipient = new Map<String, Object>{
                'email' => opp.Contact_B2C__r.Email,
                'name' => opp.Contact_B2C__r.Name,
                'recipientId' => '1',
                'routingOrder' => '1'
            };
    
            envelopeBody.put('recipients', new Map<String, Object>{
                'signers' => new List<Map<String, Object>>{ recipient }
            });
        }
    
        // Serialize the envelope body to JSON and set it in the request
        req.setBody(JSON.serialize(envelopeBody));
    
        Http http = new Http();
        HttpResponse res = http.send(req);
    
        if (res.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String envelopeId = (String) responseMap.get('envelopeId');
            
            // Retrieve the user's language
            String userLanguage = UserInfo.getLanguage();

            // Retrieve the embedded sending URL
            String embeddedSendingUrl = getEmbeddedSendingUrl(envelopeId, opportunityId);
            

          

            // Save the envelope record after callout operations
            saveEnvelopeRecord(opportunityId, envelopeId, 'Sent');
    
            return embeddedSendingUrl;
        } else {
            throw new AuraHandledException('Failed to create envelope: ' + res.getBody());
        }
    }
    
    



    

    private static String getEmbeddedSendingUrl(String envelopeId, String opportunityId, String templateId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign_eSign/restapi/v2.1/accounts/30667966/envelopes/' + envelopeId + '/views/sender');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
    
        // Base and return URL
        String baseReturnUrl = 'https://greenforce--docu.sandbox.lightning.force.com';
        String fullReturnUrl = baseReturnUrl + '/' + opportunityId;
    
        // JSON body for embedded sending view
        String body = JSON.serialize(new Map<String, Object>{
            'returnUrl' => fullReturnUrl,
            'authenticationMethod' => 'None',
            'email' => 'signer@example.com',
            'userName' => 'John Doe'
        });
    
        req.setBody(body);
    
        Http http = new Http();
        HttpResponse res = http.send(req);
    
        if (res.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseMap.get('url'); // Embedded sending URL
        } else {
            throw new AuraHandledException('Failed to get embedded sending URL: ' + res.getBody());
        }
    }
    
    

    private static HttpResponse createEnvelope(String oppName, Id opportunityId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign_eSign/restapi/v2.1/accounts/30667966/envelopes');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        Map<String, Object> customFields = new Map<String, Object>{
            'textCustomFields' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'name' => 'OpportunityId', 'value' => opportunityId }
            }
        };

        String body = JSON.serialize(new Map<String, Object>{
            'status' => 'created',
            'emailSubject' => 'Please sign the document for Opportunity: ' + oppName,
            'customFields' => customFields
        });

        req.setBody(body);

        Http http = new Http();
        return http.send(req);
    }

    private static void saveEnvelopeRecord(Id opportunityId, String envelopeId, String status) {
        if (Schema.sObjectType.dfsle__Envelope__c.isCreateable()) {
            dfsle__Envelope__c envelopeRecord = new dfsle__Envelope__c();
            if (Schema.sObjectType.dfsle__Envelope__c.fields.dfsle__DocuSignId__c.isAccessible()) {
                envelopeRecord.dfsle__DocuSignId__c = envelopeId;
            }
            if (Schema.sObjectType.dfsle__Envelope__c.fields.dfsle__SourceId__c.isAccessible()) {
                envelopeRecord.dfsle__SourceId__c = opportunityId;
            }
            if (Schema.sObjectType.dfsle__Envelope__c.fields.dfsle__Sent__c.isAccessible()) {
                envelopeRecord.dfsle__Sent__c = System.now();
            }
            insert envelopeRecord;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<dfsle__Envelope__c> getOpportunityEnvelopes(Id opportunityId) {
        if (!Schema.sObjectType.dfsle__Envelope__c.isAccessible()) {
            throw new AuraHandledException('Insufficient access rights on dfsle__Envelope__c');
        }
        return [
            SELECT Name,id,dfsle__DocuSignId__c, dfsle__Sent__c, dfsle__EmailSubject__c, Status__c
            FROM dfsle__Envelope__c
            WHERE dfsle__SourceId__c = :opportunityId
            ORDER BY dfsle__Sent__c DESC
        ];
    }

    @AuraEnabled 
    public static String getEnvelopeStatusFromDocuSign(String envelopeId) {
        if (String.isBlank(envelopeId)) {
            return 'Unknown';
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign_eSign/restapi/v2.1/accounts/30667966/envelopes/' + envelopeId);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseMap.get('status');
        } else {
            return 'Error fetching status';
        }
    }

   
    @AuraEnabled
    public static void updateEnvelopeStatuses(Id opportunityId) {
        System.enqueueJob(new UpdateEnvelopeStatusJob(opportunityId));
    }

    public class UpdateEnvelopeStatusJob implements Queueable, Database.AllowsCallouts {
        private Id opportunityId;

        public UpdateEnvelopeStatusJob(Id opportunityId) {
            this.opportunityId = opportunityId;
        }

        public void execute(QueueableContext context) {
            List<dfsle__Envelope__c> envelopes = [
                SELECT Id, dfsle__DocuSignId__c, Status__c, Documents_Retrieved__c
                FROM dfsle__Envelope__c
                WHERE dfsle__SourceId__c = :opportunityId
            ];

            for (dfsle__Envelope__c envelope : envelopes) {
                String newStatus = getEnvelopeStatusFromDocuSign(envelope.dfsle__DocuSignId__c);system.debug('Statut is completed?'+newStatus+' ID Envelope : '+envelope.dfsle__DocuSignId__c);

                if (newStatus != null && newStatus != envelope.Status__c) {
                    envelope.Status__c = newStatus;
                }

              
            }

            if (!envelopes.isEmpty() && Schema.sObjectType.dfsle__Envelope__c.isUpdateable()) {
                update envelopes;
            }
        }
    }
    @AuraEnabled
    public static String createEnvelopeFromTemplateAndGetEmbeddedSendingUrl(Id opportunityId) {
        Opportunity opp = [SELECT Name,RecordTypeId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        // Step 0 : determine templateId by recordtype

        String templateId;
    if (opp.RecordTypeId == '0129E0000019L0zQAE') {
        templateId = '160d672c-d49a-41db-8792-c3c4419e6733';
    } else if (opp.RecordTypeId == '0129E0000019L0uQAE') {
        templateId = 'e2a8eea1-f690-4c5e-b4ba-d4358be0de75';
    } else {
        throw new AuraHandledException('No template found for the specified Record Type.');
    }
        // Step 1: Create the envelope from a template in DocuSign
        HttpResponse response = createEnvelopeFromTemplate(opportunityId, templateId);

        if (response.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String envelopeId = (String) responseMap.get('envelopeId');

            // Step 2: Get the embedded sending URL
            String embeddedSendingUrl = getEmbeddedSendingUrl(envelopeId, opportunityId);

            // Step 3: Save the envelope record to Salesforce
            saveEnvelopeRecord(opportunityId, envelopeId, 'Sent');

            return embeddedSendingUrl;
        } else {
            throw new AuraHandledException('Failed to create envelope from template: ' + response.getBody());
        }
    }
    //Create envelope from template
   
    private static HttpResponse createEnvelopeFromTemplate(Id opportunityId, String templateId) {
        // Query the Opportunity and related Contact
        Opportunity opp = [
            SELECT Id, Contact_B2C__r.Email, Contact_B2C__r.Name 
            FROM Opportunity 
            WHERE Id = :opportunityId
        ];
    
        // Ensure the contact exists
        if (opp.Contact_B2C__c == null) {
            throw new IllegalArgumentException('The Opportunity does not have a Contact_B2C__c associated.');
        }
    
        // Retrieve contact details
        String contactEmail = opp.Contact_B2C__r.Email;
        String contactName = opp.Contact_B2C__r.Name;
    
        // Retrieve the current user's information
        String currentUserEmail = UserInfo.getUserEmail();
        String currentUserName = UserInfo.getName();
    
        // Create the JSON body
        String body = JSON.serialize(new Map<String, Object>{
            'status' => 'created',
            'templateId' => templateId,
            'templateRoles' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'roleName' => 'Client',
                    'email' => contactEmail,
                    'name' => contactName
                },
                new Map<String, Object>{
                    'roleName' => 'Commercial',
                    'email' => currentUserEmail,
                    'name' => currentUserName
                }
            }
        });
    
        // Setup the HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign_eSign/restapi/v2.1/accounts/30667966/envelopes');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);
    
        // Send the request
        Http http = new Http();
        return http.send(req);
    }
    
    
    private static String getEmbeddedSendingUrl(String envelopeId, String opportunityId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign_eSign/restapi/v2.1/accounts/30667966/envelopes/' + envelopeId + '/views/sender');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        String baseReturnUrl = 'https://greenforce--docu.sandbox.lightning.force.com';
        String fullReturnUrl = baseReturnUrl + '/lightning/r/Opportunity/' + opportunityId + '/view';

        // JSON body for the embedded sending URL
        String body = JSON.serialize(new Map<String, Object>{
            'returnUrl' => fullReturnUrl,
            'authenticationMethod' => 'None',
            'email' => 'signer@example.com',
            'userName' => 'John Doe'
        });

        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseMap.get('url');
        } else {
            throw new AuraHandledException('Failed to get embedded sending URL: ' + res.getBody());
        }
    }
    //Get docs
    private static void retrieveAndSaveDocumentsUsingToolkit(String envelopeId, Id opportunityId) {
        // Retrieve envelope metadata
        dfsle.Envelope envelope = dfsle.EnvelopeService.getEnvelope(envelopeId);
        List<dfsle.Document> documents = dfsle.DocumentService.getEnvelopeDocuments(envelopeId);
    
        // Loop through each document and make a callout to get the Blob
        for (dfsle.Document doc : documents) {
            // Call helper method to retrieve document content as Blob
            Blob documentBlob = downloadDocumentContentFromDocuSign(envelopeId, doc.Id);
            if (documentBlob != null) {
                saveDocumentToOpportunity(opportunityId, documentBlob, doc.Name);
            }
        }
    }
    private static void saveDocumentToOpportunity(Id opportunityId, Blob documentBlob, String documentName) {
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = documentName;
        contentVersion.PathOnClient = documentName + '.pdf';
        contentVersion.VersionData = documentBlob;
        contentVersion.IsMajorVersion = true;
        insert contentVersion;

        ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
        contentDocumentLink.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id].ContentDocumentId;
        contentDocumentLink.LinkedEntityId = opportunityId;
        contentDocumentLink.ShareType = 'I';
        insert contentDocumentLink;
    }

    // Helper method to make a REST callout to DocuSign to download document content as a Blob
private static Blob downloadDocumentContentFromDocuSign(String envelopeId, String documentId) {
    String endpoint = '/restapi/v2.1/accounts/30667966/envelopes/' + envelopeId + '/documents/' + documentId;

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:DocuSign_eSign' + endpoint);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/pdf');

    Http http = new Http();
    HttpResponse res = http.send(req);

    if (res.getStatusCode() == 200) {
        return res.getBodyAsBlob(); // Return the document content as Blob
    } else {
        System.debug('Failed to download document: ' + res.getStatusCode() + ' - ' + res.getBody());
        return null;
    }
}

   /**
     * Void a DocuSign envelope and update the status in Salesforce.
     *
     * @param envelopeId - The Salesforce record ID of the envelope
     * @param voidReason - The reason for voiding the envelope
     * @return - A success or error message
     */
@AuraEnabled
public static String voidEnvelope(String envelopeId, String voidReason) {
    Http http = new Http();
    HttpRequest request = new HttpRequest();
    
    try {
        // Fetch the envelope record
        dfsle__Envelope__c envelope = [SELECT Id, dfsle__DocuSignId__c, Status__c FROM dfsle__Envelope__c WHERE Id = :envelopeId LIMIT 1];


        if (envelope == null || String.isBlank(envelope.dfsle__DocuSignId__c) || envelope.Status__c <> 'sent') {
            return 'Envelope not found or invalid.';
        }

        // Construct the API endpoint
        String endpoint = '/restapi/v2.1/accounts/30667966/envelopes/' + envelope.dfsle__DocuSignId__c;
        request.setEndpoint('callout:DocuSign_eSign' + endpoint);

        // Set the request details
        request.setMethod('PUT');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(new Map<String, Object>{
            'status' => 'voided',
            'voidedReason' => voidReason
        }));

        // Send the HTTP request
        HttpResponse response = http.send(request);
 
        if (response.getStatusCode() == 200) {
            // Update the envelope status in Salesforce
            envelope.Status__c = 'Voided';
            update envelope;

            return 'Envelope successfully voided.';
        } else {
            return 'Error voiding envelope: ' + response.getBody();
        }
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
} 


    


}