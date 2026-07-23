Salesforce Take-Home Assignment
Part A – System Design & Architecture

A leading bank requires a CRM system to manage customers and loan requests.

The Customer__c object represents a bank customer.
The LoanRequest__c object represents a loan request associated with a customer.

The system must notify a manager whenever a loan amount exceeds ₪250,000 and record all relevant events in an Audit Log.

Tasks
Design the data model for the system, including objects, fields, and relationships.
Describe how you would implement security mechanisms to protect sensitive data and enforce access permissions.
Explain how you would implement an integration with an external loan approval system.
Part B – Problem Solving & Apex Development
Apex

Write an Apex Trigger on the LoanRequest__c object that executes whenever a loan request is created or updated.

The trigger must perform the following actions:

If the loan amount (LoanAmount__c) is greater than ₪250,000, create a Task assigned to the bank manager.
If the loan status changes to "Approved", send an email notification to the customer confirming the approval.
Whenever the loan status changes, create an Audit__c record containing the loan request details and the customer's name.
Tasks
Write Apex code that satisfies all of the above requirements.
Ensure the implementation supports bulk operations (bulkification) and properly handles exceptions.
Explain how you would ensure the code is efficient, scalable, and production-ready.
Part C – Flow for Loan Request Management
Flow

Create an automated Flow that performs the following actions whenever the loan request status (LoanStatus__c) changes:

If the request is Approved, update Customer__c.Status__c to "Active Customer".
If the request is Rejected, update the status to "Requires Additional Review".
If the loan amount exceeds ₪250,000, send an automatic notification to the manager and create an Audit__c record.
Tasks
Build the Flow using an optimal design with Decision elements and proper exception handling.
Include a screenshot of the completed Flow showing its structure and the connections between all elements and decision branches.
Provide a short document explaining the main Flow steps.
Part D – LWC Development with Component Communication
Interactive Loan Request Form

Develop a Lightning Web Component (LWC) solution that implements the following requirements.

1. Loan Request Form

Create a form that allows users to enter:

Customer Name
Loan Amount
Loan Status

A Save button should submit the data to the Salesforce LoanRequest__c object.

2. Saving Data via Apex

When the user clicks Save:

The data must be sent to Salesforce through an Apex controller.
Implement an Apex class that receives the data from the component, creates a LoanRequest__c record, and stores it in Salesforce.
3. Communication Between LWC Components

Component A

Displays the loan request form.
After clicking Save, sends the entered data to Component B.

Component B

Receives the data from Component A.
Displays:
Customer Name
Loan Amount
Loan Status

Important: The two components must not share a common parent component.

4. Data Refresh

After saving the record in Salesforce:

Reload the latest data from Salesforce.
Component B must display the updated information retrieved from Salesforce.
5. User Experience (UX/UI)
Ensure the interface is clean, intuitive, and includes all required fields.
Display a loading spinner while the system is processing or saving data.
Tasks
Write the complete code for all required LWC components.
Write the Apex code needed to save the data by creating a LoanRequest__c record.
Provide documentation describing the code structure and any implementation challenges you encountered.
Part E – Testing & Optimization (20 Points)
Unit Tests & Performance Optimization

Write Unit Tests that verify:

A Task is created when the loan amount exceeds ₪250,000.
The customer's status is updated to "Active Customer" when a loan request is approved.
Data is correctly passed between the LWC components.
The application properly handles incomplete or invalid input data.

Additionally, explain how you would improve system performance when processing large data volumes, including topics such as:

Batch Apex
SOQL Governor Limits
Database Indexing
Submission Guidelines

Submit the following in .txt or .docx format:

Apex code
Flow
LWC components
Flow

Include:

A screenshot of the completed Flow.
A brief document explaining the main Flow steps.
LWC Components

Submit:

The complete source code for both components.
A concise explanation of the code structure and underlying logic.

Finally, ensure your solution achieves at least 90% Apex code coverage through Unit Tests.