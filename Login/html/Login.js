$(function() {
$(document).click(function(e) {
if ($("#Login_submenu").is(":visible")) {
	$("#Login_submenu").hide(); 
}
});
$("body").delegate("#Login_name", "click", function() {
	$("#Login_submenu").toggle();
});
$("body").delegate("#Login_menu", "click", function(e) {
	e.stopPropagation();
});
});

