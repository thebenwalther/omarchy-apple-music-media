import QtQuick
import qs.Ui

Toggle {
  id: root

  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.description: description
  Accessible.focusable: true
  Accessible.focused: activeFocus
  Accessible.checkable: true
  Accessible.checked: checked
  Accessible.ignored: !visible
  Accessible.onToggleAction: clicked()
  Accessible.onPressAction: clicked()
}
