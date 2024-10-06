v1.0

B9s is a K9s-like tool for limited-access Linux systems

Usage:
- HOME should always take you back to the first screen. You can also press the ESC key to go home. EXIT will..well..exit
- Use arrow keys and enter/return key to navigate
- Tab will move your cursor to the OK/Cancel/HOME/EXIT options below

NOTE:
- List of objects does not refresh automatically
- If logs are long and you quit before all are loaded, it might take a little bit for it to try to finish showing logs...
    - If needed you can ctrl+c and restart the app
- Not all options are available like in K9s
- There are effectively no keyboard shortcuts options available for this. Some letters are indicated will work, but numbers do not
- When viewing logs of a pod, it will **follow**. To break the follow, press ctrl+c and then it's the normal 'less' command (q to quit)
- Default namespace selected is 'default'. You may select one or more in the namespaces tab to view multiple

>>> Reminder: This was a quick weekend project because I wanted it. It only has some of the common uses of k9s"
