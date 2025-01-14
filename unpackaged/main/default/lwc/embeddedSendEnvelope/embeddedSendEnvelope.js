import { LightningElement, api, track, wire } from 'lwc';
import createEnvelopeAndGetEmbeddedSendingUrl from '@salesforce/apex/DocuSignService.createEnvelopeAndGetEmbeddedSendingUrl';
import createEnvelopeFromTemplateAndGetEmbeddedSendingUrl from '@salesforce/apex/DocuSignService.createEnvelopeFromTemplateAndGetEmbeddedSendingUrl';
import getOpportunityEnvelopes from '@salesforce/apex/DocuSignService.getOpportunityEnvelopes';
import updateEnvelopeStatuses from '@salesforce/apex/DocuSignService.updateEnvelopeStatuses';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class EmbeddedSendEnvelope extends LightningElement {
    @api recordId;
    @track envelopes; 
    @track error;
    @track loading = false;

    columns = [
        { label: 'Name', fieldName: 'recordLink', type: 'url', typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' } },
        { label: 'Email Subject', fieldName: 'dfsle__EmailSubject__c', type: 'text' },
        { label: 'Sending Date', fieldName: 'dfsle__Sent__c', type: 'date' },
        { label: 'Status', fieldName: 'Status__c', type: 'text' }
    ];

    @wire(getOpportunityEnvelopes, { opportunityId: '$recordId' })
    wiredEnvelopes(result) {
        this.envelopeResult = result;
        if (result.data) {
            this.envelopes = result.data.map(env => ({
                ...env,
                recordLink: `/lightning/r/dfsle__Envelope__c/${env.Id}/view`
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.envelopes = undefined;
        }
    }

    get isRefreshDisabled() {
        return !this.envelopes || this.envelopes.length === 0;
    }

    handleCreateEnvelope() {
        this.loading = true;
        createEnvelopeAndGetEmbeddedSendingUrl({ opportunityId: this.recordId })
            .then(result => {
                window.location.href = result;
                this.loading = false;
            })
            .catch(error => {
                this.loading = false;
                this.handleError(error);
            });
    }

    handleCreateEnvelopeFromTemplate() {
        
        this.loading = true;
        createEnvelopeFromTemplateAndGetEmbeddedSendingUrl({ opportunityId: this.recordId })
            .then(result => {
                window.location.href = result;
                this.loading = false;
            })
            .catch(error => {
                this.loading = false;
                this.handleError(error);
            });
    }

    handleRefresh() {
        this.loading = true;
        updateEnvelopeStatuses({ opportunityId: this.recordId })
            .then(() => refreshApex(this.envelopeResult))
            .catch(error => {
                this.handleError(error);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleError(error) {
        this.showToast('Error', error.body ? error.body.message : error.message, 'error');
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }
}