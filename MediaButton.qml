import QtQuick
import qs.Ui

Button {
  id: root

  property string accessibleName: tooltipText || text || "Button"

  Accessible.role: Accessible.Button
  Accessible.name: accessibleName
  Accessible.focusable: focusable
  Accessible.focused: activeFocus
  Accessible.selected: selected
  Accessible.ignored: !visible
  Accessible.onPressAction: clicked()
}
