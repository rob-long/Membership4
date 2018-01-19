$(document).ready(function(){
    $(".CartDelete").click(function(){
	id = this.id.split("_")[1];
	var helpid = "CartDeleteHelp_" + id;
	//alert("displaying "+helpid);
	$('#'+helpid).toggle();
    });
});
