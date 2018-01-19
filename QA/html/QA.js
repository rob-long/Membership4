<!--

$(document).ready(function(){
    $(".select_question").click(function(){
	var cid = this.id.split("_")[2];
	var feeinfo = $(this).html();
	add_question(this,cid,feeinfo);
    });
    $("#new_format").change(function(){
	change_format(this);
    });
    $("#make_question").click(function(){
	make_question(this);
    });
});

function add_question (obj,id,name) {
    //alert("adding question " + id + " " + name);
    //mark original as added
    $(obj).addClass("selected");
    //add a delete function
    var qlist = $('ol#selected_questions');
    var input = "<input type='hidden' name='question' value='" + id + "'>";
    var required = "<input type='checkbox' name='required' value='" + id + "'>";
    var delicon = "<span class='delQuestion'></span>";
    qlist.append("<li>" + required + name + input + delicon + "</li>");
    qlist.find(":last-child .delQuestion").click(function(){
	$(this).parent().remove();
    });
}

var allow_size = { 'short text':1, 'long text':1, 'select':0, 'multiselect':1, 'radio':0, 'radio+other':0, 'checkbox':0, 'checklist':0, 'checklist+other':0, 'password':1, 'hidden':0, 'label':0, 'preformatted':0 };
var allow_validate = { 'short text':1, 'long text':0, 'select':0, 'multiselect':0, 'radio':0, 'radio+other':0, 'checkbox':0, 'checklist':0, 'checklist+other':0, 'password':0, 'hidden':0, 'label':0, 'preformatted':0 };
var allow_value = { 'short text':0, 'long text':0, 'select':1, 'multiselect':1, 'radio':1, 'radio+other':1, 'checkbox':0, 'checklist':1, 'checklist+other':1, 'password':0, 'hidden':0, 'label':0, 'preformatted':0 };
var allow_answer = { 'short text':0, 'long text':0, 'select':0, 'multiselect':0, 'radio':0, 'radio+other':0, 'checkbox':1, 'checklist':0, 'checklist+other':0, 'password':0, 'hidden':1, 'label':1, 'preformatted':1 };

function change_format (obj) {
    var format = $(obj).attr("value");
    //alert("changing format to " + format);
    var size = $('#new_size');
    var validate = $('#new_validate');
    var value = $('#new_value');
    var answer = $('#new_answer');
    if (allow_size[format]) {
	size.removeAttr("disabled");
	size.parent().show();
    }
    else {
	size.attr("disabled","disabled");
	size.parent().hide();
    }
    if (allow_validate[format]) {
	validate.removeAttr("disabled");
	validate.parent().show();
    }
    else {
	validate.attr("disabled","disabled");
	validate.parent().hide();
    }
    if (allow_value[format]) {
	value.removeAttr("disabled");
	value.parent().show();
    }
    else {
	value.attr("disabled","disabled");
	value.parent().hide();
    }
    if (allow_answer[format]) {
	answer.removeAttr("disabled");
	answer.parent().show();
    }
    else {
	answer.attr("disabled","disabled");
	answer.parent().hide();
    }
}

function make_question (obj) {
    var fdata = get_form_data("wizard",1);
    var format = fdata['new_format'];
    format = format.replace(/\+/g," ");
    var post = "format=" + format + "&label=" + fdata['new_prompt'] + "&qa_lib_id=" + fdata['new_lib'];
    if (allow_size[format]) {
	post = post.concat("&size=" + fdata['new_size']);
    }
    if (allow_validate[format]) {
	post = post.concat("&value=" + fdata['new_validate']);
    }
    else if (allow_value[format]) {
	post = post.concat("&value=" + fdata['new_value']);
    }
    else if (allow_answer[format]) {
	post = post.concat("&value=" + fdata['new_answer']);
    }
    var posturl = document.URL + "&_bare=2";
    sendAsyncPost(posturl,"new_question",post);
}

function sendAsyncPost(url,id,postdata) {
    var xmlObj = createRequestObj(); // from httprequest.js
    xmlObj.onreadystatechange= function() { 
        if (xmlObj.readyState==4) {
            if (xmlObj.status==200) {
                update_new_question(xmlObj, id);
	    }
	    else {
//		$('#new_question').append("<div class='error'>" + url + " failed: status " + xmlObj.status);
		$('#new_question').append("<div class='error'>Failed: status " + xmlObj.status);
	    }
	}
    }
    xmlObj.open("POST",url,false);
    xmlObj.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
    //xmlObj.setRequestHeader("Content-length", postdata.length);
    //xmlObj.setRequestHeader("Connection", "close");
    xmlObj.send(postdata);
    return xmlObj;
}

function update_new_question(req, id) {
    //document.getElementById(id).innerHTML = req.responseText;
    var newq = $('#new_question');
    // update pane
    newq.html(req.responseText);
    // enable event handlers on new content
    newq.find("#new_format").change(function(){
	change_format(this);
    });
    newq.find("#make_question").click(function(){
	make_question(this);
    });
    // update questions pane
    var fdata = get_form_data("wizard",1);
    var lib = fdata["new_qa_lib_id"];
    var qid = fdata["new_question_id"];
    var label = fdata["new_question_label"];
    label = label.replace(/\+/g," ");
    var libel = "ul#qa_lib_"+lib;
    $(libel).append('<li><span id="qa_base_'+qid+'" class="select_question selected">'+label+'</span></li>\n');

    // update selected questions
    $("ol#selected_questions").append('<li><input type="checkbox" name="required" value="'+qid+'">'+label+'<input type="hidden" name="question" value="'+qid+'"><span class="delQuestion"></span>\n');

    // handlers
    $(libel + " .select_question:last").click(function(){
	var cid = this.id.split("_")[2];
	var feeinfo = $(this).html();
	add_question(this,cid,feeinfo);
    });
    $(".delQuestion:last").click(function(){
	$(this).parent().remove();
    });
}

function get_form_data (form_id,escape) {
    var f = false;
    var length = document.forms.length;
    for (var i = 0; i < length; i++) {
	if (document.forms[i].id == form_id) {
            f = document.forms[i];
	}
    }
    var fdata = {};
    for ( var i = 0; i < f.elements.length; i++ ) {
	var e = f.elements[i];
	var name = e.name;
	var val = e.value;
	if (escape) {
	    val = val.replace(/&/g,"%26");
	    val = val.replace(/=/g,"%3D");
	    val = val.replace(/\+/g,"%2B");
	    val = val.replace(/ /g,"+");
	}
	fdata[name] = val;
    }
    return fdata;
}

//-->

