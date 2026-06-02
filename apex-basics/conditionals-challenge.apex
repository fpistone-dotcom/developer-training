//Requirement #1.6: Harry Potter Conditions

//In the Developer Console, write a program that will sort a Student into the correct Hogwart's House based upon whether or not they are Mischievous vs. Noble, and whether or not they are Brave vs. Cunning.

//Characteristics	     House
//Brave & Noble	         Hufflepuff
//Brave & Mischievous	 Gryffindor
//Noble & Cunning	     Ravenclaw
//Cunning & Mischievous	 Slytherin


String characteristics1 = 'Cunning';
String characteristics2 = 'Mischievous';
String house = '';

if ((characteristics1 == 'Brave' && characteristics2 == 'Mischievous') || (characteristics2 == 'Brave' && characteristics1 == 'Mischievous')) {
    house = 'Gryffindor';
} else if ((characteristics1 == 'Brave' && characteristics2 == 'Noble') || (characteristics2 == 'Brave' && characteristics1 == 'Noble')) {
    house = 'Hufflepuff';
} else if ((characteristics1 == 'Noble' && characteristics2 == 'Cunning') || (characteristics2 == 'Noble' && characteristics1 == 'Cunning')) {
    house = 'Ravenclaw';
} else if ((characteristics1 == 'Cunning' && characteristics2 == 'Mischievous') || (characteristics2 == 'Cunning' && characteristics1 == 'Mischievous')) {
    house = 'Slytherin';
} else {
    house = 'Default';
}

System.debug('The Student is in... ' + house + '!!!!');