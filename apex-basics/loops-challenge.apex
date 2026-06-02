//Requirement #1.7: Looping over Lists
//Using a traditional 'for' loop, iterate over the luckyNumberList List we created in the Collections lesson and print out each number in the List.
List<Integer> luckyNumberList = new List<Integer>();
luckyNumberList.add(4);
luckyNumberList.add(8);
luckyNumberList.add(15);
luckyNumberList.add(16);
luckyNumberList.add(23);
luckyNumberList.add(42);

for (Integer i = 0; i < luckyNumberList.size(); i++) {
    System.debug('Lucky Number: ' + luckyNumberList[i]);
}

//Repeat this exercise using an advanced 'for' loop.
for (Integer luckyNumber : luckyNumberList) {
    System.debug('Lucky Number: ' + luckyNumber);
}       

//Requirement #1.8: Looping over Sets
//Using an advanced 'for' loop, iterate over the daysOfTheWeek Set we created in the Collections lesson and print out each value in the Set.
Set<String> daysOfTheWeek = new Set<String>();
daysOfTheWeek.add('Monday');
daysOfTheWeek.add('Tuesday');
daysOfTheWeek.add('Wednesday');
daysOfTheWeek.add('Thursday');
daysOfTheWeek.add('Friday');
daysOfTheWeek.add('Saturday');
daysOfTheWeek.add('Sunday');

for (String day : daysOfTheWeek) {
    System.debug('Day of the week: ' + day);
}

//Loop over daysOfTheWeek and create a new Map where the value is day of the week (i.e. "Monday") and the key is the numerical representation (1 = Sunday, 2 = Monday, etc.)
Map<Integer, String> dayMap = new Map<Integer, String>();
Integer dayIndex = 1;
for (String day : daysOfTheWeek) {
    dayMap.put(dayIndex, day);
    dayIndex++;
}

//Using a traditional 'for' loop, loop over your newly created Map using the iterator to print out the day of the week (i.e. "Monday")
for (Integer i = 1; i <= dayMap.size(); i++) {
    System.debug('Day of the week: ' + dayMap.get(i));
}


//Requirement #1.9: Looping over Maps
//Using the distanceFromSunMapInAu we created in this exercise and advance for loops, perform the following:
Map<String, Decimal> distanceFromSunMapInAu = new Map<String, Decimal>{
    'Mercury' => 0.39,
    'Venus' => 0.72,
    'Earth' => 1,
    'Mars' => 1.52,
    'Jupiter' => 5.2,
    'Saturn' => 9.54,
    'Uranus' => 19.2,
    'Neptune' => 30.06
};

//Print out the closest planet to the sun
String closestPlanet = '';
Decimal closestDistance;
for (String planet : distanceFromSunMapInAu.keySet()) {
    Decimal distance = distanceFromSunMapInAu.get(planet);
    if (distance < closestDistance || closestDistance == null) {
        closestDistance = distance;
        closestPlanet = planet;
    }
}
System.debug('The closest planet to the sun is: ' + closestPlanet);

//Print out the farthest planet from the sun
String farthestPlanet = '';
Decimal farthestDistance = 0;
for (String planet : distanceFromSunMapInAu.keySet()) {
    Decimal distance = distanceFromSunMapInAu.get(planet);
    if (distance > farthestDistance) {
        farthestDistance = distance;
        farthestPlanet = planet;
    }
}
System.debug('The farthest planet from the sun is: ' + farthestPlanet);

//Create a List of all planets that are more than 3 au from the sun
List<String> distantPlanets = new List<String>();
for (String planet : distanceFromSunMapInAu.keySet()) {
    Decimal distance = distanceFromSunMapInAu.get(planet);
    if (distance > 3) {
        distantPlanets.add(planet);
    }
} 
System.debug('Planets that are more than 3 au from the sun: ' + distantPlanets);