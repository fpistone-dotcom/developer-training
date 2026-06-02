/* 
Requirement #1.1: 
Create variables to store the following and print each one out to the Developer Console to test your code:
Your name in capital letters
Number of characters in your name
Favorite Holiday Date
Favorite Holiday Date plus 30 days
Whether the current year is a leap year
Number of siblings you have
The square root of number of siblings you have
Your User record's username 
*/


//Your name in capital letters
String myName = 'Fran'; 
String myNameUpperCase = myName.toUpperCase();

//Number of characters in your name
Integer numCharsInName = myName.length();

//Favorite Holiday Date
Date favoriteHolidayDate = Date.newInstance(2025, 12, 25);

//Favorite Holiday Date plus 30 days
Date favoriteHolidayDatePlus30 = favoriteHolidayDate.addDays(30);

//Whether the current year is a leap year
Integer currentYear = Date.today().year(); 
Boolean isLeapYear = Date.isLeapYear(currentYear);

//Number of siblings you have
Double numSiblings = 2;

//The square root of number of siblings you have
Double sqrtNumSiblings = Math.sqrt(numSiblings);

//Your User record's username 
String myUsername = UserInfo.getUserName();