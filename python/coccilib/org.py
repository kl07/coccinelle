def build_link(p, msg, color) :
	return "[[view:%s::face=%s::linb=%s::colb=%s::cole=%s][%s]]" % (p[0].file,color,p[0].line,p[0].column,p[0].column_end,msg)

def print_todo(p, msg="", color="ovl-face1") :
	link = build_link(p, msg, color)
	print "* TODO %s" % (link)

def print_link(p, msg="", color="ovl-face1") :
	print (build_link(p, msg, color))

#
# print_main, print_sec and print_secs
# will be deprecated.
#
def print_main(msg, p, color="ovl-face1") :
	oldmsgfmt = "%s %s::%s" % (msg,p[0].file,p[0].line)
	print_todo(p, oldmsgfmt, color)

def print_sec(msg, p, color="ovl-face2") :
	print_link(p, msg, color)

def print_secs(msg, ps, color="ovl-face2") :
	for i in ps:
		print_link (i, msg, color)