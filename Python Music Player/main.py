import os
from tkinter import *
from tkinter import filedialog
from pygame import mixer


filename=''
Paused=False

###Functions##

def browse_files():
	global filename
	filename= filedialog.askopenfilename()
	statusbar['text']= os.path.basename(filename)+" Loaded "
	print(os.path.basename(filename)+' 1')

def on_closing():
    stop_btnStop()
    root.destroy()

def play_btnPlay():
	try:
		Paused
	except:
		try:
			mixer.music.load(filename)
			mixer.music.play()
			print(os.path.basename(filename)+' 2')
			statusbar['text']= "Now Playing "+ os.path.basename(filename)
		except:
			print("Error")
	else:
		mixer.music.unpause()
		statusbar['text']= "Now Playing "+ os.path.basename(filename)
		print(str(Paused))
		Paused=False

def pause_btnPause():
	global Paused
	Paused = False
	mixer.music.pause()
	print (Paused)
	statusbar['text']= os.path.basename(filename)+" Paused"

def stop_btnStop():
	mixer.music.stop()
	statusbar['text']= "Music Stopped "+"Last song was: "+os.path.basename(filename)

def set_vol(val):
	volume = int(val)/100
	mixer.music.set_volume(volume)



###End of Functios###

root = Tk()	 # Initialize Tkinter
mixer.init() # Initialize music mixer

# Create Menu Bar
menubar= Menu(root)
root.config(menu=menubar)

# Create submenu
subMenu= Menu(menubar,tearoff = 0)
menubar.add_cascade(label='File', menu=subMenu)
subMenu.add_command(label='Open',command= browse_files)
subMenu.add_command(label='Exit',command = on_closing )

subMenu= Menu(menubar,tearoff = 0)
menubar.add_cascade(label='Help', menu=subMenu)
subMenu.add_command(label='About us')


# Main Window 
root.geometry('200x650')
root.title('MusicPy Player by MCMWebDev')
root.iconbitmap(r'MPlayer.ico')

text = Label(root,text='Lets make some noise!!')
text.pack()

photo = PhotoImage(file='MPlayer.png')
labelphoto = Label(root,image = photo)
labelphoto.pack()

#Buttons variables
	#Icons
playButton= PhotoImage(file='play-icon.png')
pauseButton= PhotoImage(file='pause-icon.png')
stopButton= PhotoImage(file='stop-icon.png')

	#Buttons commands
btnPlay = Button(root, text ='Play', image = playButton,command = play_btnPlay)
btnPause = Button(root, text ='Pause', image = pauseButton,command = pause_btnPause)
btnStop = Button(root, text ='Pause', image = stopButton,command = stop_btnStop)
volScale = Scale(root, from_=0, to=100, orient=HORIZONTAL,command =set_vol)

statusbar= Label(root,text="Welcome to MusicPy "+filename+".",relief=SUNKEN,anchor=W)

volScale.set(25)


btnPlay.pack()
btnPause.pack()
btnStop.pack()
volScale.pack()
statusbar.pack(side=BOTTOM, fill=X)


root.protocol("WM_DELETE_WINDOW", on_closing)
root.mainloop()

