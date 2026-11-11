import QtQuick

// Sits behind a popup's visible content, filling the whole (now-fullscreen)
// PanelWindow, and fires outsideClicked() for any press that lands on it --
// i.e. anywhere the popup's own content box isn't covering. Pulled out once
// here instead of duplicating the same background MouseArea and reasoning
// in every popup under popups/, power/, and launcher/.
//
// This alone is not enough: a click on blank space *inside* the visible
// content box would otherwise fall through to this MouseArea too (a plain
// Rectangle does not itself accept mouse events, so hit-testing moves on to
// whatever handles input behind it). Every popup's own content Rectangle
// carries a small swallowing MouseArea of its own for that reason -- that
// part can't be factored out here, since it has to sit inside each popup's
// own content item to intercept before the point reaches this one.
MouseArea {
    signal outsideClicked()

    anchors.fill: parent
    onClicked: outsideClicked()
}
