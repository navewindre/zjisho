# zjisho
a tool to create japanese definitions using jisho api

usage:

```
zjisho [-d <definition_count> -s <senses_count>] <word>
```

example:

```
~ » zjisho 開く     
開く（ひらく） - to open/to undo/to unseal, to bloom/to unfold/to spread out, to open (for business, e.g. in the morning), to be wide (gap, etc.)/to widen, etc...
~ » zjisho -s 1 -d 1 死ぬ
死ぬ（しぬ） - to die, etc...
```

there is also an included zjisho-clipboard script, which uses xclip to replace a japanese term in the clipboard with zjisho output.
