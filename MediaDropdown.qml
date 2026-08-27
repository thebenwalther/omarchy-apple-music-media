import QtQuick
import qs.Ui

Dropdown {
  id: root

  property string accessibleName: label || "Selection"

  Accessible.role: Accessible.ComboBox
  Accessible.name: accessibleName
  Accessible.description: currentLabel()
  Accessible.focusable: true
  Accessible.ignored: !visible
  Accessible.onPressAction: toggle()
}
