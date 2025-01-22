import { LightningElement, api, track } from 'lwc';
import voidEnvelope from '@salesforce/apex/DocuSignService.voidEnvelope';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class VoidDocusignEnvelope extends LightningElement {
    @api recordId; // Salesforce dfsle__Envelope__c record ID
    @track voidReason = ''; // Track the void reason input by the user

    handleReasonChange(event) {
        this.voidReason = event.target.value; // Capture the text area value
    }

    handleVoidEnvelope() {
        if (!this.voidReason) {
            this.showToast('Error', 'Please provide a reason for voiding the envelope.', 'error');
            return;
        }

        voidEnvelope({ envelopeId: this.recordId, voidReason: this.voidReason })
            .then((result) => {
                this.showToast('Success', result, 'success');
                this.refreshPage();
            })
            .catch((error) => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    refreshPage() {
        eval("$A.get('e.force:refreshView').fire();");
    }
}