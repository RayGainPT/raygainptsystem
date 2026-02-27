from pathlib import Path
s=Path('lib/screens/booking_screen.dart').read_text()
needle='return Theme('
idx=s.find(needle)
if idx==-1:
    print('return Theme( not found')
else:
    start=idx + s[idx:].find('(')  # position of (
    # find matching )
    depth=0
    for i in range(start, len(s)):
        ch=s[i]
        if ch=='(':
            depth+=1
        elif ch==')':
            depth-=1
            if depth==0:
                print('Matching ) at index', i, 'line', s.count('\n',0,i)+1)
                print('Context:\n', s[max(0,i-120):i+40])
                break
    else:
        print('No matching ) found after return Theme(')
