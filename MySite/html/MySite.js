var d = new Date();
var lccstart = parseInt(d.getTime()/1000) - 2;
window.setInterval(function() { checkForSitemapChanges() },5000);
function checkForSitemapChanges() {
    var lcc = getLcc();
    if (lcc) {
	if (lcc > lccstart) {
	    // last content change is after this page was loaded
	    var alertbox = document.getElementById('reloadAlert');
	    if (alertbox) {
		alertbox.style.display = 'block';
	    }
	}
    }
}
function getLcc() {
    var name = "lcc=";
    var decodedCookie = decodeURIComponent(document.cookie);
    var ca = decodedCookie.split(';');
    for(var i = 0; i <ca.length; i++) {
        var c = ca[i];
        while (c.charAt(0) == ' ') {
            c = c.substring(1);
        }
        if (c.indexOf(name) == 0) {
            return c.substring(name.length, c.length);
        }
    }
    return 0;
}
// DEPRECATED; not needed now that MySite uses OverlayFrames
//var info_done = { };
//$(document).ready(function(){
//    $("ul.tv a").click(function(){loadPopup(this);});
//    $("ul.tv a").magnificPopup({type:"inline"});
//});
function loadPopup (obj) {
//    alert($("#contentPopup_1495").html());

//<div class="toolbar"><div aria-label="tool bar" class="btn-toolbar" role="toolbar"><div aria-label="tool group" role="group" class="btn-group">
//<a class="btn btn-sm btn-default"><span class="fa fa-fw fa-pencil"></span>edit</a>
//<a class="btn btn-sm btn-default"><span class="fa fa-fw fa-copy"></span>copy</a>
//<a class="btn btn-sm btn-default"><span class="fa fa-fw fa-check"></span>approve</a>
//<a class="btn btn-sm btn-default tone-bad"><span class="fa fa-fw fa-trash-o tone-bad"></span>DELETE</a>
//</div>
//</div>

    var name = $(obj).attr("href");
    var cid = name.split("_")[1];
    if (! info_done[cid]) {
	var info = content_info["content_"+cid];
	var url = info["aurl"];
	var Status = info["status"].charAt(0).toUpperCase() + info["status"].slice(1);
	$("#contentPopup_"+cid).append("<h1>" + info["title"] + "</h1>");

	var tools = 
            "<a class='btn btn-sm btn-default' href='"+url+cid+"&cmd=preview' target='_blank'><span class='fa fa-fw fa-eye'></span>preview</a>" + 
            "<a class='btn btn-sm btn-default' href='"+url+cid+"&cmd=update' target='_blank'><span class='fa fa-fw fa-pencil'></span>edit</a>" + 
            "<a class='btn btn-sm btn-default' href='"+url+cid+"&cmd=conf'><span class='fa fa-fw fa-cog'></span>configure</a>" + 
            "<a class='btn btn-sm btn-default' href='"+url+cid+"&cmd=publish'><span class='fa fa-fw fa-download'></span>publish</a>" + 
            "<a class='btn btn-sm btn-default' href='"+url+cid+"&cmd=rollback'><span class='fa fa-fw fa-arrow-left'></span>rollback</a>" + 
            "<a class='btn btn-sm btn-default' href='"+url+cid+"&cmd=delete'><span class='fa fa-fw fa-trash-o'></span>delete</a>";

	$("#contentPopup_"+cid).append('<div class="toolbar"><div aria-label="tool bar" class="btn-toolbar" role="toolbar"><div aria-label="tool group" role="group" class="btn-group">' + tools + "</div></div>");
	var data = 
	    "<tr><th>Type</th><td>"+info["type"]+"</td></th>" +
	    "<tr><th>Status</th><td><span class='status"+Status+"'>"+info["status"]+"</span></td></th>" +
	    "<tr><th>Language</th><td>"+info["lang"]+"</td></th>" +
	    "<tr><th>Menu Label</th><td>"+info["label"]+"</td></th>" +
	    "<tr><th>Path</th><td>"+info["path"]+"</td></th>" +
	    "<tr><th>URL</th><td><a href='"+info["curl"]+"' target='_blank'>"+info["curl"]+"</a></td></th>";
	var footer = "";
	if (info["plugin"]) {
	    footer = "<p>Content on this page is managed by the <a href='" + modpath + "/" + info["plugin"] + "?id=" + cid + "'>" + info["plugin"] + "</a> plug-in.</p>"; 
// + "<div class='appLaunchLink' id='app_" + info["plugin"] + "'>launch</div>";
// include launcher.js and add click event for this new launcher link
	}
	$("#contentPopup_"+cid).append("<table class='pageInfo'>" + data + "</table>" + footer);
	info_done[cid] = 1;
    }
};
