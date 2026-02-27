from pathlib import Path
p=Path(r'C:/Users/guerz/OneDrive/Desktop/ZenStay/lib/screens/booking_screen.dart')
s=p.read_text()
stack=[]
line=1
for i,ch in enumerate(s):
    if ch=='\n':
        line+=1
    if ch in '({[':
        stack.append((ch,line,i))
    elif ch in ')}]':
        if not stack:
            print('Unmatched closing',ch,'at line',line)
            break
        open_ch,open_line,open_idx=stack.pop()
        pairs={')':'(',']':'[','}':'{'}
        if pairs[ch]!=open_ch:
            print('Mismatched',open_ch,'opened at',open_line,'but closed by',ch,'at',line)
            break
else:
    if stack:
        oc,ol,oi=stack[-1]
        print('Unclosed',oc,'opened at line',ol)
    else:
        print('All brackets balanced')
