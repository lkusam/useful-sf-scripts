// Email APEX class to make emails invalid

List<Contact> contacts = [SELECT Id, Email FROM Contact WHERE Email != null AND Email NOT LIKE '%.invalid'];

//  Making all the email invalid 

for(contact con: contacts){
con.email += '.invalid';
}

update contacts;