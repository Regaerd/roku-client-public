 ' This code is adapted from the Roku SDK web_server example app.
 ' Original notices from that example are copied below.

 ' Roku Streaming Player Web Server
 ' This code was heavily influenced by darkhttpd/1.7
 ' The darkhttpd copyright notice is included below.

 '
 ' darkhttpd
 ' copyright (c) 2003-2008 Emil Mikulic.
 '
 ' Permission to use, copy, modify, and distribute this software for any
 ' purpose with or without fee is hereby granted, provided that the
 ' above copyright notice and this permission notice appear in all
 ' copies.
 '
 ' THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
 ' WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
 ' WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
 ' AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 ' DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
 ' PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
 ' TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 ' PERFORMANCE OF THIS SOFTWARE.
 '

 ' Adapted from C to Brightscript with mods by Roku, Inc.

function ClassReply()
    this = m.ClassReply
    if this=invalid
         this = CreateObject("roAssociativeArray")
        ' constants
        this.class       = "Reply"
        this.GENERATED   = 1
        this.FROMFILE    = 2
        this.CONCATFILES = 3
        this.WAITING     = 4
        this.source      = 0
        ' members
        this.buf         = invalid
        this.header      = invalid
        this.path        = invalid
        this.request     = invalid
        this.id          = 0
        this.files       = invalid
        this.headers     = invalid
        ' copy-initializable members
        this.start       = 0
        this.length      = 0
        this.sent        = 0
        this.header_sent = 0
        this.header_only = false
        this.buf_start   = 0
        this.buf_offset  = 0
        this.http_code   = 0
        this.mimetype    = "text/html" ' for errors
        ' functions
        this.init      = reply_init
        this.process   = reply_process
        this.get       = reply_process_get
        this.default   = reply_default
        this.redirect  = reply_redirect
        this.send      = reply_send
        this.sendHdr   = reply_send_header
        this.genDir    = reply_generate_directory_listing
        this.genHdr    = reply_generate_header
        this.done      = reply_done
        this.doneHdr   = reply_done_header
        this.isWaiting = reply_waiting
        this.log       = reply_log
        this.simpleOK  = reply_simple_ok
        this.preflight = reply_handle_cors_preflight
        ' html lines
        this.keepAlive = reply_keep_alive
        this.genBy     = reply_generated_by
        ' handlers for path prefixes
        this.handlers  = {}
        this.AddHandler= reply_add_handler
        ' singleton
        m.ClassReply   = this
    end if
    this.id = this.id + 1
    return this
end function

function InitReply(request as Object) as Object
    this = CreateObject("roAssociativeArray")
    this.append(ClassReply())
    this.init(request)
    return this
end function

function reply_init(request)
    m.buf = CreateObject("roByteArray")
    m.request = request
    m.headers = CreateObject("roAssociativeArray")
end function

function reply_send(sock as Object, bufsize as Integer) as Integer
    sent = -1
    if m.source=m.FROMFILE
        if m.start+m.sent>=m.buf_start+m.buf.count()
            m.buf_start = m.start+m.sent
            m.buf.ReadFile(m.path,m.buf_start,bufsize)
            info(m,"Read" + Stri(m.buf.count()) + " bytes from source file @" + tostr(m.buf_start))
        end if
    else if m.source=m.CONCATFILES
        if m.start + m.sent >= m.buf_offset + m.buf_start + m.buf.count()
            file = m.files.GetHead()
            if m.start + m.sent >= m.buf_offset + file.length
                m.buf_offset = m.buf_offset + file.length
                m.buf_start = 0
                m.files.RemoveHead()
                file = m.files.GetHead()
            else
                m.buf_start = m.start + m.sent - m.buf_offset
            end if

            m.buf.ReadFile(file.path, m.buf_start, bufsize)
            info(m,"Read" + Stri(m.buf.count()) + " bytes from source file @" + tostr(m.buf_start))
        end if
    end if
    buf_pos = m.start + m.sent - m.buf_start - m.buf_offset
    buf_remaining = m.buf.count() - buf_pos
    if buf_remaining=0 then info(m,"source buf is empty")
    req_remaining = m.length - m.sent
    if buf_remaining>req_remaining then buf_remaining = req_remaining
    sent = sock.send(m.buf, buf_pos, buf_remaining)
    m.log(sent, m.buf_offset+m.buf_start+buf_pos, m.length)
    if sent>0 then m.sent = m.sent + sent
    return sent
end function

function reply_send_header(sock as Object, bufsize as Integer) as Integer
    if m.header_sent=0
        sent = sock.sendStr(m.header)
    else
        sent = sock.sendStr(m.header.mid(m.header_sent))
    end if
    m.log(sent, m.header_sent, m.header_length)
    if sent>0 then m.header_sent = m.header_sent + sent
    return sent
end function

 ' ---------------------------------------------------------------------------
 ' A default reply for any (erroneous) occasion.
 '
function reply_default(errcode as Integer, reason as String)
    errname = HttpTitle(errcode)

    buf = "<html><head><title>" + Stri(errcode).trim() + " " + errname + "</title></head><body>" + UnixNL()
    buf =  buf + "<h1>" + errname + "</h1>" + UnixNL()
    buf =  buf + reason + UnixNL()
    buf =  buf + "<hr>" + UnixNL()
    buf =  buf + m.genBy() + UnixNL()
    buf =  buf + "</body></html>" + UnixNL()

    m.buf.fromasciistring(buf)
    m.length = m.buf.count()

    m.genHdr(true)
    m.source = m.GENERATED
end function

function reply_redirect(where as String)
    m.location = where
    message = "Moved to: <a href="+ Chr(34) + where + Chr(34) + ">" + where + "</a>"
    m.default(301,message)
end function

function reply_keep_alive(close as Boolean) as String
    if close then base = "Connection: close" else base = "Keep-Alive: timeout=" + Stri(Global("idletime")).trim()
    return base
end function

function reply_generate_header(close=false as Boolean)
    code = m.http_code
    title = HttpTitle(code)
    m.header = "HTTP/1.1" + Stri(code) + " " + title + WinNL()
    m.header = m.header + "Date: " + m.now + WinNL()
    m.header = m.header + "Server: " + Global("pkgname") + WinNL()
    if isstr(m.location) then m.header = m.header + "Location: " + m.location + WinNL()
    m.header = m.header + m.keepAlive(close) + WinNL()
    m.header = m.header + "Content-Length:" + Stri(m.length) + WinNL()
    if code=206 then m.header = m.header + "Content-Range: bytes" + makeRange(m.start,m.length,m.filelength) + WinNL()
    m.header = m.header + "Content-Type: " + m.mimetype + WinNL()
    m.header = m.header + "Accept-Ranges: bytes" + WinNL()
    if m.request.fields["Origin"] <> invalid then m.header = m.header + "Access-Control-Allow-Origin: *" + WinNL()

    for each name in m.headers
        m.header = m.header + name + ": " + m.headers[name] + WinNL()
    next

    m.header = m.header + WinNL()
    m.header_length = m.header.len()
end function

function reply_generated_by()
    return "generated by " + Global("pkgname") + " on " + m.now
end function

function reply_generate_directory_listing() as Boolean
    fs = CreateObject("roFilesystem")
    dirList = fs.GetDirectoryListing(m.path)
    if dirList=invalid
        m.default(500,"Couldn't list directory")
        return false
    end if

    ' for tabbed alignment of file sizes
    maxlen = 0
    for each item in dirList
        il = item.len()
        if maxlen < il maxlen = il
    end for

    listing = "<html>" + UnixNL()
    listing = listing + "<head>" + UnixNL()
    listing = listing + "<title>" + Global("serverName") + "</title>" + UnixNL()
    listing = listing + "</head>" + UnixNL()
    listing = listing + "<body>" + UnixNL()
    listing = listing + "<h1>" + URLUnescape(m.request.uri) + "</h1>" + UnixNL()
    listing = listing + "<tt><pre>" + UnixNL()

    dir = m.path.getString()
    if dir.len()>0 and dir.right(1)<>"/" then dir = dir + "/"
    uriDir = m.request.uri
    if  uriDir.len()>0 and uriDir.right(1)<>"/" then uriDir = uriDir + "/"

    for each item in dirList
        if item.left(1)<>"."
            indicator = invalid
            stat = fs.stat(dir + item)
            if stat<> invalid
                if stat.doesexist("type") and stat.type="directory"
                    indicator = "/"
                else if stat.doesexist("size")
                    indicator = string(maxlen-item.len()," ") + Stri(stat.size)
                end if
            end if
            if indicator<>invalid
                uri = uriDir + item
                safe_url = uri
                listing = listing + "<a href=" + Chr(34) + safe_url + Chr(34) + ">" + item
                listing = listing + indicator
                listing = listing + "</a>" + UnixNL()
            else
                warn(m,"insufficient stat info to include '" + dir + item + "'")
            end if
        end if
    end for

    listing = listing + "</pre></tt>" + UnixNL()
    listing = listing + "<hr>" + UnixNL()

    listing = listing + m.genBy() + UnixNL()
    listing = listing + "</body>" + UnixNL()
    listing = listing + "</html>" + UnixNL()

    m.buf.FromAsciiString(listing)
    m.length = m.buf.count()

    m.http_code = 200
    m.genHdr()
    m.source = m.GENERATED
    return true
end function

 ' ---------------------------------------------------------------------------
 ' Process a GET/HEAD reply
 '
function reply_process_get() as Boolean
    ' work out path of file being requested
    req = m.request
    uri = req.uri
    decoded_uri = UrlUnescape(uri)
    path = CreateObject("roPath",Global("wwwroot")+decoded_uri)
    fs = CreateObject("roFilesystem")

    ' make sure it's safe
    if not path.isValid()
        m.default(400, "You requested an invalid URI: " + uri)
        return false
    else if not fs.exists(path)
        m.default(404, "The URI you requested (" + uri + ") was not found.")
        return false
    end if

    stat = fs.stat(path)
    if stat=invalid
        m.default(500, "fstat() failed.")
        return false
    end if
    m.path = path

    if stat.type="directory"
        m.mimetype = MimeType(Global("index_name"))
        m.genDir()
        return true
    else if stat.type="file"
        m.mimetype = MimeType(decoded_uri)
        m.fileLength = stat.size
        info(m,"uri="+uri+", target="+path+", content-type="+m.mimetype+", content-length="+Stri(m.fileLength).trim())
    else
        m.default(403, "Not a regular file.")
        return false
    end if

    m.source = m.FROMFILE
    m.lastmod = Now() ' stat.mtime (mod date not yet available)
    fileFinish = m.fileLength - 1

    ' check for If-Modified-Since, may not have to send */
    if_mod_since = req.fields["If-Modified-Since"]
    if if_mod_since<>invalid
        reqDate = date_rfc1123(if_mod_since)
        if reqDate<>invalid and reqDate.toSeconds() >= m.lastMod.toSeconds()
            m.header_only = true
            lastMod = rfc1123_date(m.lastMod)
            info(m,"not modified since " + lastMod)
            m.default(304, "not modified since " + lastMod)
            return true
        end if
    end if

    if req.range_begin_given or req.range_end_given
        if req.range_begin_given and req.range_end_given
            ' 100-200
            start = req.range_begin
            finish = req.range_end
            ' clamp finish to fileFinish
            if finish>fileFinish then finish = fileFinish
        else if req.range_begin_given and not req.range_end_given
            ' 100- :: yields 100 to end
            start = req.range_begin
            finish = fileFinish
        else if not req.range_begin_given and req.range_end_given
            ' -200 :: yields last 200
            finish = fileFinish
            start = finish - req.range_end + 1
            ' check for wrapping
            if start>finish start = 0
        else
            errx(1, "internal error - range start/finish logic inconsistency")
        end if

        m.start = start
        m.length = finish - start + 1
        m.http_code = 206

        info(m,"sending range " + makeRange(start,m.length,m.fileLength))
    else ' no range stuff
        m.length = m.fileLength
        m.http_code = 200
    end if

    m.genHdr()
    return true
end function

 ' ---------------------------------------------------------------------------
 ' Process a reply: build the header and the reply
 '
function reply_process()
    m.now = rfc1123_date(Now())
    method = m.request.method

    if method = "HEAD" then
        m.header_only = true
    end if

    if method = "OPTIONS" then
        return m.preflight()
    end if

    ' See if we've registered a handler for this path
    path = UrlUnescape(m.request.uri)
    for each prefix in m.handlers
        if left(path, len(prefix)) = prefix then
            m.fn = m.handlers[prefix]
            return m.fn()
        end if
    next

    if method=""
        m.default(400, "You sent a request that the server couldn't understand.")
    else if method="GET" or method="HEAD"
        m.get()
    else if method="OPTIONS" or method="POST" or method="PUT" or method="DELETE" or method="TRACE" or method="CONNECT"
        m.default(501, "The method you specified ("+method+") is not implemented.")
    else
        m.default(400, method+" is not a valid HTTP/1.1 method.")
    end if
end function

function reply_done() as Boolean
    return m.sent=m.length AND NOT m.isWaiting()
end function

function reply_done_header() as Boolean
    return m.header_sent=m.header_length
end function

function reply_waiting() as Boolean
    return m.source = m.WAITING
end function

function makeRange(start as Integer, length as Integer, total as Integer)
    return tostr(start) + "-" + tostr(start+length-1) + "/" + tostr(total)
end function

function reply_log(recent as Integer,from as Integer, total as Integer)
    info( m, "Sent" + Stri(recent) + " [" + makeRange(from,recent,total) +"]" )
end function

sub reply_add_handler(prefix as String, fn as Function)
    m.handlers[prefix] = fn
end sub

sub reply_simple_ok(body)
    m.buf.fromasciistring(body)
    m.length = m.buf.count()
    if validint(m.http_code) = 0 then m.http_code = 200
    m.source = m.GENERATED
    m.genHdr(true)
end sub

function reply_handle_cors_preflight()
    ' We'll be super permissive
    m.headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS, HEAD"
    m.headers["Access-Control-Max-Age"] = "1209600"

    if m.request.fields["Access-Control-Request-Headers"] <> invalid then
        m.headers["Access-Control-Allow-Headers"] = m.request.fields["Access-Control-Request-Headers"]
    end if

    m.buf.fromasciistring("")
    m.length = m.buf.count()
    m.http_code = 200
    m.genHdr(true)
    m.source = m.GENERATED

    return true
end function
