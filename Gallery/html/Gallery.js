<!--

$(document).ready(function(){
    // remove hrefs from gallery links
    $(".gallery_link").each(function(index){
	$(this).attr("name",$(this).attr("href"));
	$(this).removeAttr("href");
    });
    // add alternate click function to load the img
    $(".gallery_link").click(function(){
	var imgurl = $(this).attr("name");
	$("#gallery_viewer").html("<div id='gallery_viewer_close'></div><img src='"+imgurl+"'>");
	$("#gallery_overlay").fadeIn();
	$("#gallery_viewer").fadeIn();
    });
    // close viewer
    $("#gallery_viewer").click(function(){
	$(this).fadeOut();
	$("#gallery_overlay").fadeOut();
    });
});

//-->
