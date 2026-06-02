
//Requirement #1.2: Lists

//Create a List that holds 5 of your favorite foods
List<String> favoriteFoods = new List<String>{'Asado', 'Sushi', 'Pasta', 'Ice Cream', 'Brownie'};

//Add "Tacos" to your List
favoriteFoods.add('Tacos');

//Find the number of elements in your List and store this value in an Integer variable
Integer numFavoriteFoods = favoriteFoods.size();

//Print out your 3rd favorite food
System.debug ('My 3rd favorite food is: ' + favoriteFoods[2]);

//Find the index of "Tacos" in the List and print it out
Integer indexOfTacos = favoriteFoods.indexOf('Tacos');
System.debug('The index of Tacos is: ' + indexOfTacos);

//Remove the 2nd element from the List
favoriteFoods.remove(1);

//Using a List Constructor, create a duplicate of your List
List<String> duplicateFavoriteFoods = new List<String>(favoriteFoods);



//Requirement #1.3: Sets

//Create a Set that holds 5 items that are in your refrigerator (or you wish were in your refrigerator!)
Set<String> fridgeItems = new Set<String>{'Milk', 'Eggs', 'Dulce de Leche', 'Butter', 'Yogurt'};

//Add "Tacos" to your Set
fridgeItems.add('Tacos');

//Add all items from the Requirement #1 List to your Set
fridgeItems.addAll(favoriteFoods);

//Print out your Set to verify that "Tacos" was not added twice
System.debug('Fridge Items: ' + fridgeItems);

//Find out whether your Set contains all the elements of the List and store the results in a Boolean variable. Print this out.
Boolean setContainsAllListElements = fridgeItems.containsAll(favoriteFoods);
System.debug('Does the Set contain all elements of the List?: ' + setContainsAllListElements);   

//Remove all the elements in your Set that exist in the List
fridgeItems.removeAll(favoriteFoods);

//Print out whether or not the Set still has elements 
System.debug('Is the Set empty? True or False: ' + fridgeItems.isEmpty());



//Requirement #1.4: Maps

//Create a Map where they key is a The Simpsons character name and the value is the character's age.
/*
Character Name	Character Age
Homer Simpson	36
Marge Simpson	34
Bart Simpson	10
Lisa Simpson	8
Maggie Simpson	1
*/
Map<String, Integer> simpsonsCharacters = new Map<String, Integer>{
    'Homer Simpson' => 36,
    'Marge Simpson' => 34,
    'Bart Simpson' => 10,
    'Lisa Simpson' => 8,
    'Maggie Simpson' => 1
};

//Print out Marge's age
Integer margeAge = simpsonsCharacters.get('Marge Simpson');
System.debug('Marge Simpson is ' + margeAge + ' years old.');

//Print out all the ages of the characters
System.debug('Ages of the characters: ' + simpsonsCharacters.values());

//Update the Map so that Maggie is now 2 years old
simpsonsCharacters.put('Maggie Simpson', 2);    

//Remove Lisa from the Map
simpsonsCharacters.remove('Lisa Simpson');

//Add "Moe Szyslak" to the Map. He is 62 years old
simpsonsCharacters.put('Moe Szyslak', 62);

//Print out the total number of Characters in the Map
Integer numCharactersInMap = simpsonsCharacters.size();
System.debug('Total number of characters in the Map: ' + numCharactersInMap);



//Requirement #1.5: More Map Fun

//Create a new Map where the key is the name of a TV Show and the value is a List of characters that appear in that show.
Map<String, List<String>> tvShowsCharacters = new Map<String, List<String>>();

//Add the TV show The Simpsons to your Map
tvShowsCharacters.put('The Simpsons', new List<String>(simpsonsCharacters.keySet()));

/*
Add the TV show Game Of Thrones to your Map with the following Characters:
    Jon Snow
    Arya Stark
    Tyrion Lannister
    Daenerys Targaryen
    Eddard Stark
*/
tvShowsCharacters.put('Game Of Thrones', new List<String>{'Jon Snow', 'Arya Stark', 'Tyrion Lannister', 'Daenerys Targaryen', 'Eddard Stark'});

//Add another TV show of your choice to the Map with at least 3 Characters
tvShowsCharacters.put('Dexter', new List<String>{'Dexter Morgan', 'Debra Morgan', 'Rita Bennett', 'Harry Morgan', 'Masuka'});

//Remove "Eddard Stark" from the TV Show Game of Thrones in the Map
List<String> gameOfThrones = tvShowsCharacters.get('Game Of Thrones');
gameOfThrones.remove(gameOfThrones.indexOf('Eddard Stark'));
tvShowsCharacters.put('Game Of Thrones', gameOfThrones);


//Add "Ned Flanders" to The Simpsons
List<String> simpsonsCharactersList = tvShowsCharacters.get('The Simpsons');
simpsonsCharactersList.add('Ned Flanders');
tvShowsCharacters.put('The Simpsons', simpsonsCharactersList);

//Print out all the characters in your favorite TV Show
List<String> favoriteTVShowCharacters = tvShowsCharacters.get('Dexter');
System.debug('Characters in my favorite TV show: ' + favoriteTVShowCharacters);

//Print out the second Character in The Simpsons
String secondSimpsonsCharacter = simpsonsCharactersList[1];
System.debug('The second character in The Simpsons is: ' + secondSimpsonsCharacter);    

//Create a new List that holds all of the characters from all TV Shows
List<String> allCharacters = new List<String>();
allCharacters.addAll(tvShowsCharacters.get('Game Of Thrones'));
allCharacters.addAll(tvShowsCharacters.get('The Simpsons'));
allCharacters.addAll(tvShowsCharacters.get('Dexter'));
System.debug('All characters from all TV shows: ' + allCharacters);

//Create a new Set that only holds the characters from The Simpsons and Game of Thrones
Set<String> simpsonsAndGoTCharacters = new Set<String>();
simpsonsAndGoTCharacters.addAll(tvShowsCharacters.get('The Simpsons'));
simpsonsAndGoTCharacters.addAll(tvShowsCharacters.get('Game Of Thrones'));
System.debug('Characters from The Simpsons and Game of Thrones: ' + simpsonsAndGoTCharacters);  

//finished