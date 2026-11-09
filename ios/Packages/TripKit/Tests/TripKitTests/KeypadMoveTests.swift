import Testing
@testable import TripKit

/// The expense editor's own keypad and the system keyboard (`ExpenseEditor`): the pad goes the other way from
/// the keyboard, on the keyboard's timing; another app's keyboard moves nothing, and a keyboard going down as the
/// sheet closes from its own buttons brings no pad back.
@Suite struct KeypadMoveTests {
    @Test func anotherAppsKeyboardMovesNothing() {
        #expect(KeypadMove.on(keyboardShows: true, isLocal: false, padShown: true, leaving: false, duration: 0.25) == .stay)
        #expect(KeypadMove.on(keyboardShows: false, isLocal: false, padShown: false, leaving: false, duration: 0.25) == .stay)
    }

    @Test func aKeyboardNotSaidToBeAnotherAppsCounts() {
        #expect(KeypadMove.on(keyboardShows: true, isLocal: nil, padShown: true, leaving: false, duration: 0.25) == .move(shown: false, duration: 0.25))
        #expect(KeypadMove.on(keyboardShows: true, isLocal: true, padShown: true, leaving: false, duration: 0.25) == .move(shown: false, duration: 0.25))
    }

    @Test func thePadAlreadyWhereAskedStays() {
        #expect(KeypadMove.on(keyboardShows: true, isLocal: true, padShown: false, leaving: false, duration: 0.25) == .stay)
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: true, leaving: false, duration: 0.25) == .stay)
    }

    @Test func theKeyboardGoingDownAsTheSheetLeavesBringsNoPad() {
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: false, leaving: true, duration: 0.25) == .stay)
    }

    @Test func theKeyboardGoingDownBringsThePadBack() {
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: false, leaving: false, duration: 0.25) == .move(shown: true, duration: 0.25))
    }

    /// hiding the pad is always allowed, leaving or not
    @Test func theKeyboardRisingWhileLeavingStillHidesThePad() {
        #expect(KeypadMove.on(keyboardShows: true, isLocal: true, padShown: true, leaving: true, duration: 0.25) == .move(shown: false, duration: 0.25))
    }

    @Test func noDurationMovesWithNoCurve() {
        #expect(KeypadMove.on(keyboardShows: true, isLocal: true, padShown: true, leaving: false, duration: 0) == .move(shown: false, duration: nil))
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: false, leaving: false, duration: -1) == .move(shown: true, duration: nil))
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: false, leaving: false, duration: nil) == .move(shown: true, duration: nil))
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: false, leaving: false, duration: .nan) == .move(shown: true, duration: nil))
    }

    @Test func theKeyboardsDurationIsTheCurves() {
        #expect(KeypadMove.on(keyboardShows: true, isLocal: true, padShown: true, leaving: false, duration: 0.25) == .move(shown: false, duration: 0.25))
        #expect(KeypadMove.on(keyboardShows: false, isLocal: true, padShown: false, leaving: false, duration: 0.35) == .move(shown: true, duration: 0.35))
    }
}
