var runcount = 0;
$(document).ready(function(){
    $(".calendarArchiveMonth").click(function(){
	runcount++;
        if ($(this).hasClass("hasEvents")) {
	    if ($(this).children("a").length() == 0) {
		// no link, but we do have events to link to
		//alert(this.id + "runcount: " +runcount);
		var id = this.id;
		var date = id.split("_");
		var urlpath = calendar_url.split("/");
		var month = urlpath.pop();
		var year = urlpath.pop();
		var today = new Date();
		var yeardiff = Math.abs(year - today.getFullYear());
		var newurl;
		if (month >= 1 && month <= 12 && yeardiff >= 0 && yeardiff <= 10) {
		    // change date
		    urlpath.push(date[1],date[2]);
		}
		else {
		    // append date
		    urlpath.push(year,month,date[1],date[2]);
		}
		newurl = urlpath.join("/");
		//alert(newurl);
		window.location = newurl;
            }
	    // else, already has a regular link target
	}
        else {
           alert("No events in this month.");
        }
    });
});
