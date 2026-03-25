//
//  PresetCategoryAppRestartTests.swift
//  VocableUITests
//
//  Created by Canan Arikan on 7/8/22.
//  Copyright © 2022 WillowTree. All rights reserved.
//

import XCTest
import Foundation

class PresetCategoryAppRestartTests: XCTestCase {
    
    let category = "General"
    /// First preset category in the default list (before General).
    let firstPresetCategory = "Kids"
    /// Second preset category after Kids was added at the start of the list.
    let secondCategory = "General"
    let phrase = "Test"
    
    // To avoid resetting the app on restart, we'll need to pass in new launch arguments
    let disableAnimationsOnly = Arguments(.disableAnimations)
    
    override func setUp() {
        let app = XCUIApplication()
        app.configure {
            Arguments(.resetAppDataOnLaunch, .disableAnimations)
        }
        continueAfterFailure = false
        app.launch()
    }
    
    func testAddedPhrasePersists() throws {
        // Navigate to our test category and add a phrase
        try SettingsScreen.navigateToSettingsCategoryScreen()
        try SettingsScreen.openCategorySettings(category: category)
        CustomCategoriesScreen.editCategoryPhrasesButton.tap()
        try CustomCategoriesScreen.addPhrase(phrase)
        
        // Verify that phrase does exist in Category Details Screen
        XCTAssertTrue(CustomCategoriesScreen.phraseDoesExist(phrase))
        
        // Verify that phrase does exist in Main Screen
        try CustomCategoriesScreen.returnToMainScreenFromEditPhrases()
        MainScreen.locateAndSelectDestinationCategory(.general)
        XCTAssertTrue(MainScreen.phraseDoesExist(phrase))
        
        // Restart the app
        Utilities.restartApp(withLaunchArguments: disableAnimationsOnly)
        
        // Verify that the added phrase persists after restarting
        MainScreen.locateAndSelectDestinationCategory(.general)
        XCTAssertTrue(MainScreen.phraseDoesExist(phrase))
    }
    
    func testMySayingsAddedPhrasePersists() throws {
        let category = "My Sayings"
        // Navigate to our test category and add a phrase
        try SettingsScreen.navigateToSettingsCategoryScreen()
        try SettingsScreen.openCategorySettings(category: category)
        CustomCategoriesScreen.editCategoryPhrasesButton.tap()
        try CustomCategoriesScreen.addPhrase(phrase)
        
        // Verify that phrase does exist in Category Details Screen
        XCTAssertTrue(CustomCategoriesScreen.phraseDoesExist(phrase))
        
        // Verify that phrase does exist in Main Screen
        try CustomCategoriesScreen.returnToMainScreenFromEditPhrases()
        MainScreen.locateAndSelectDestinationCategory(.mySayings)
        XCTAssertTrue(MainScreen.phraseDoesExist(phrase))
        
        // Restart the app
        Utilities.restartApp(withLaunchArguments: disableAnimationsOnly)
        
        // Verify that the added phrase persists after restarting
        MainScreen.locateAndSelectDestinationCategory(.mySayings)
        XCTAssertTrue(MainScreen.phraseDoesExist(phrase))
    }
    
    func testRecentsAddedPhrasePersists() {
        // Navigate to General and tap first phrase
        MainScreen.locateAndSelectDestinationCategory(.general)
        let firstPhrase = XCUIApplication().collectionViews.staticTexts.element(boundBy: 0).label
        XCUIApplication().collectionViews.staticTexts[firstPhrase].tap()
        
        // Verif that Recents shows the tapped phrase (first phrase of General)
        MainScreen.locateAndSelectDestinationCategory(.recents)
        XCTAssertTrue(MainScreen.phraseDoesExist(firstPhrase))
        
        // Restart the app
        Utilities.restartApp(withLaunchArguments: disableAnimationsOnly)
        
        // Verify that the tapped phrase persists after restarting
        MainScreen.locateAndSelectDestinationCategory(.recents)
        XCTAssertTrue(MainScreen.phraseDoesExist(firstPhrase))
    }
    
    func testHideCategoryPersists() throws {
        // Navigate to our test category
        try SettingsScreen.navigateToSettingsCategoryScreen()
        
        // Verify that when the first preset category is shown, up button is disabled and down button is enabled
        VTAssertReorderArrowsEqual(.downEnabledOnly, for: firstPresetCategory)
        
        // Hide the preset category
        try SettingsScreen.openCategorySettings(category: category)
        SettingsScreen.showCategoryButton.tap()
        SettingsScreen.navBarBackButton.tap()
        
        // Verify that when the category is hidden, up and down buttons are disabled
        VTAssertReorderArrowsEqual(.none, for: category)
        
        // Restart the app
        Utilities.restartApp(withLaunchArguments: disableAnimationsOnly)
        
        // Verify that after restart, hidden category's up and down buttons are disabled
        try SettingsScreen.navigateToSettingsCategoryScreen()
        VTAssertReorderArrowsEqual(.none, for: category)
    }
    
    func testReorderPersists() throws {
        // Navigate to our test category
        try SettingsScreen.navigateToSettingsCategoryScreen()
        
        // Verify that first preset category's up button is disabled and down button is enabled
        VTAssertReorderArrowsEqual(.downEnabledOnly, for: firstPresetCategory)
        
        // Verify that second preset category's (second in the list) up and down buttons are enabled
        VTAssertReorderArrowsEqual(.both, for: secondCategory)
        
        // Reorder categories, move first preset category to the second of the list
        let firstCategory = try SettingsScreen.locateCategoryCell(firstPresetCategory)
        firstCategory.buttons[.settings.editCategories.moveDownButton].tap()
        try SettingsScreen.navBarBackButton.assertExistence(timeout: 1.0)
        
        // Verify that moved category (now second in the list) up and down buttons are enabled
        VTAssertReorderArrowsEqual(.both, for: firstPresetCategory)
        
        // Verify that second preset category (now first in the list) up button is disabled and down button is enabled
        VTAssertReorderArrowsEqual(.downEnabledOnly, for: secondCategory)
        
        // Restart the app and navigate to Settings Category Screen
        Utilities.restartApp(withLaunchArguments: disableAnimationsOnly)
        try SettingsScreen.navigateToSettingsCategoryScreen()
        
        // Verify that moved category (now second in the list) up and down buttons are enabled
        VTAssertReorderArrowsEqual(.both, for: firstPresetCategory)
        
        // Verify that second preset category (now first in the list) up button is disabled and down button is enabled
        VTAssertReorderArrowsEqual(.downEnabledOnly, for: secondCategory)
    }
    
    func testRenameCategory() throws {
        let categoryName = "Basic Needs"
        let nameSuffix = "add"
        let renamedCategory = categoryName + nameSuffix
        let categoryIdentifier = (CategoryIdentifier.basicNeeds).identifier
        
        //Rename the preset category
        try SettingsScreen.navigateToSettingsCategoryScreen()
        try SettingsScreen.openCategorySettings(category: categoryName)
        try SettingsScreen.renameCategoryButton.tapWhenExists()
        try KeyboardScreen.typeText(nameSuffix)
        try KeyboardScreen.checkmarkAddButton.tapWhenExists()
        XCTAssertEqual(SettingsScreen.title.label, renamedCategory)
        
        // Confirm that the category is renamed from categories list
        try SettingsScreen.navBarBackButton.tapWhenExists()
        XCTAssertTrue(try SettingsScreen.doesCategoryExist(renamedCategory))
        
        // Confirm that the category is renamed from main screen
        try CustomCategoriesScreen.returnToMainScreenFromCategoriesList()
        MainScreen.locateAndSelectDestinationCategory(.basicNeeds)
        let isSelectedPredicate = NSPredicate(format: "isSelected == true")
        let query = XCUIApplication().cells.containing(isSelectedPredicate)
        XCTAssertEqual(query.staticTexts.element.label, renamedCategory)
        XCTAssertEqual(MainScreen.selectedCategoryCell.identifier, categoryIdentifier)
        
        // Restart the app and navigate to Settings Category Screen
        Utilities.restartApp(withLaunchArguments: disableAnimationsOnly)
        try SettingsScreen.navigateToSettingsCategoryScreen()
        
        // Confirm that the renamed category name persists
        try CustomCategoriesScreen.returnToMainScreenFromCategoriesList()
        MainScreen.locateAndSelectDestinationCategory(.basicNeeds)
        XCTAssertEqual(query.staticTexts.element.label, renamedCategory)
    }
}
