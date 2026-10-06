import os
HERE=os.path.join(os.environ["TEMP"],"vozn")
p=r"C:\Code\Drones\scripts\game_config.gd"
s=open(p,encoding="utf8",newline="").read()
crlf="\r\n" in s
t=s.replace("\r\n","\n")
entry=open(os.path.join(HERE,"map_entry.gd.txt"),encoding="utf8").read().replace("\r\n","\n")
start=t.index("## This map depicts the south-eastern approach to Voznesensk")
end_marker='\n},\n}\n'
j=t.index(end_marker,start)
# the old entry ends with "\t},\n},\n" right before the MAPS-closing "}" ; keep the closing "}" 
new=t[:start]+entry+t[j+len('\n},\n'):]
if crlf: new=new.replace("\n","\r\n")
open(p,"w",encoding="utf8",newline="").write(new)
print("replaced; size",len(new))
