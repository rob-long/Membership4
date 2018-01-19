(function($){
	$.CMenu = function(options){
		var settings = {
			animation : 0,
			animation_speed: 200,
			animation_main_menu_only: 0,
			include_mobile_menu : 0,
			mobile_menu_animation_speed : 500
		};
		if (options) {
			$.extend(settings,options);
		}
		if (settings.include_mobile_menu){
			$("a#CMenuMBClose").click(function(){
				$("#CMenuMobileM").hide("fade",{direction : "right", complete : function(){$("a#CMenuMB").show();}},settings.mobile_menu_animation_speed);
			});
			$("a#CMenuMB").click(function(){
				$("a#CMenuMB").hide();
				$("#CMenuMobileM").show("fade",{direction:"right"},settings.mobile_menu_animation_speed);
			});
		}
		$("ul#CMenu > li > ul").hide();
		var vertical_menu = $("ul#CMenu").hasClass("CMenu_vertical") ? true : false;

		if( /Android/i.test(navigator.userAgent) ) {
			$(".CMenu li").click(function(event){
				if ($(this).find("ul:first").length != 0 && $(this).find("ul:first").attr("class") != "mobile_clicked") {
					event.preventDefault();
				}
				
				if (vertical_menu){
					$(this).find("ul:first").css({"position" : "absolute","top" : "0px","left" : $(this).find("a.menu:first").width() + "px"});
				}else{
					if (!$(this).parent().hasClass("CMenu")){
						$(this).find("ul:first").css({"position" : "absolute","top" : "0px","left" : $(this).find("a.menu:first").width() + "px"});
					}
				}

				if ($(this).parent("ul:first").attr("class") != "mobile_clicked") {
					$(".mobile_clicked").css("z-index","0").hide();
					$(".mobile_clicked").removeClass("mobile_clicked");
				}

				$('html, body').one('click', function() {
					$(".mobile_clicked").css("z-index","0").hide();
					$(".mobile_clicked").removeClass("mobile_clicked");
				});

				$(this).find("ul:first").css("z-index","1000").show();		
				$(this).find("ul:first").toggleClass("mobile_clicked");
		
				event.stopPropagation();
			});
		}
		else {
			$(".CMenu li").hover(function(){
				var elem = $(this).find("ul:first");
				if (vertical_menu){
					$(this).find("ul:first").css({"position" : "absolute","top" : "0px","left" : $(this).find("a.menu:first").width() + "px"});
				}else{
					if (!$(this).parent().hasClass("CMenu")){
						$(this).find("ul:first").css({"position" : "absolute","top" : "0px","left" : $(this).find("a.menu:first").width() + "px"});
					}
				}

				if (settings.animation){
					if (!vertical_menu && !$(this).parent().hasClass("CMenu")){
						if (!settings.animation_main_menu_only){
							$(this).find("ul:first").css("z-index","1000").animate({width: "toggle"},settings.animation_speed);
						}else{
							$(this).find("ul:first").css("z-index","1000").show();
						}
					}else{
						$(this).find("ul:first").css("z-index","0").slideDown(settings.animation_speed).stop(true,true);
					}
				}else{
					$(this).find("ul:first").css("z-index","1000").show();
				}
			},function(){
				if (settings.animation){
					if (!vertical_menu && !$(this).parent().hasClass("CMenu")){
						if (!settings.animation_main_menu_only){
							$(this).find("ul:first").css("z-index","0").animate({width: "toggle"},settings.animation_speed);
						}else{
							$(this).find("ul:first").css("z-index","0").hide();
						}
					}else{
						$(this).find("ul:first").css("z-index","0").slideUp(settings.animation_speed);
					}
				}else{
					$(this).find("ul:first").css("z-index","0").hide();
				}
			});
		}
	}
})(jQuery);
