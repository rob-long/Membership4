<!--

// setup basic jquery event handlers

$(document).ready(function(){
//    $(".select_question").click(function(){
//	var cid = this.id.split("_")[2];
//	var feeinfo = $(this).html();
//	add_question(this,cid,feeinfo);
//    });
    $("#format").change(function(){
	change_format(this);
    });
    $("#prompt").blur(function(){
	set_input_name(this);
    });
    $(".copyQuestion").click(function(){
	copy_question(this);
    });
    $(".popupLink").magnificPopup({type:"inline"});

//    $("#make_question").click(function(){
//	make_question(this);
//    });
});

// OLD: add a question from a library

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

// question attributes allowed for each format type

var allow_size = { 
    'short text':1,
    'long text':1,
    'select':0,
    'multiselect':1,
    'radio':0,
    'radio+other':0,
    'checkbox':0,
    'checklist':0,
    'checklist+other':0,
    'password':1,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':1,
    'range':0,
    'date':0,
    'time':0,
    'url':1,
    'email':1
};
var allow_maxlen = { 
    'short text':1,
    'long text':1,
    'select':0,
    'multiselect':0,
    'radio':0,
    'radio+other':0, // allow for other?
    'checkbox':0,
    'checklist':0,
    'checklist+other':0, // allow for other?
    'password':1,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':0,
    'range':0,
    'date':0,
    'time':0,
    'url':1,
    'email':1
};
var allow_datatype = { 
    'short text':1,
    'long text':0,
    'select':0,
    'multiselect':0,
    'radio':0,
    'radio+other':0,
    'checkbox':0,
    'checklist':0,
    'checklist+other':0,
    'password':0,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':0,
    'range':0,
    'date':0,
    'time':0,
    'url':0,
    'email':0
 };
var allow_options = {
    'short text':0,
    'long text':0,
    'select':1,
    'multiselect':1,
    'radio':1,
    'radio+other':1,
    'checkbox':0,
    'checklist':1,
    'checklist+other':1,
    'password':0,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':0,
    'range':0,
    'date':0,
    'time':0,
    'url':0,
    'email':0
 };
var allow_preset = {
    'short text':1,
    'long text':1,
    'select':1,
    'multiselect':1,
    'radio':1,
    'radio+other':1,
    'checkbox':1,
    'checklist':1,
    'checklist+other':1,
    'password':1,
    'hidden':1,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':1,
    'range':1,
    'date':1,
    'time':1,
    'url':1,
    'email':1
};
var allow_required = { 
    'short text':1,
    'long text':1,
    'select':1,
    'multiselect':1,
    'radio':1,
    'radio+other':1,
    'checkbox':1,
    'checklist':1,
    'checklist+other':1,
    'password':1,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':1,
    'number':1,
    'range':1,
    'date':1,
    'time':1,
    'url':1,
    'email':1
 };
var allow_placeholder = {
    'short text':1,
    'long text':0,
    'select':0,
    'multiselect':0,
    'radio':0,
    'radio+other':0,
    'checkbox':0,
    'checklist':0,
    'checklist+other':0,
    'password':0,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':0,
    'range':0,
    'date':0,
    'time':0,
    'url':1,
    'email':1
 };
var allow_checked = {
    'short text':0,
    'long text':0,
    'select':0,
    'multiselect':0,
    'radio':0,
    'radio+other':0,
    'checkbox':1,
    'checklist':0,
    'checklist+other':0,
    'password':0,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':0,
    'range':0,
    'date':0,
    'time':0,
    'url':0,
    'email':0
 };
var allow_min = { // also used for max, step
    'short text':0,
    'long text':0,
    'select':0,
    'multiselect':0,
    'radio':0,
    'radio+other':0,
    'checkbox':0,
    'checklist':0,
    'checklist+other':0,
    'password':0,
    'hidden':0,
    'label':0,
    'preformatted':0,
    'file':0,
    'number':1,
    'range':1,
    'date':0,
    'time':0,
    'url':0,
    'email':0
 };

// words to disregard when shortening a question to a name

var nullwords = new Array('please','enter','input','tell',
    'a','able','all','also','am','an','and','any','are','as','at','be','been','both',
    'but','by','can','could','couldn','did','didn','do','does','doesn','doing','don',
    'done','each','else','etc','even','ever','for','from','get','gets','go','going',
    'gone','got','had','hadn','has','hasn','have','haven','having','he','her','here',
    'hers','him','his','how','if','in','into','is','isn','it','its','itself','just',
    'less','let','may','more','most','much','must','new','next','no','none',
    'nor','not','of','on','onto','or','other','s','say','seem','seemed','seems','shall',
    'she','should','shouldn','since','so','some','soon','t','than','that','thats',
    'the','their','theirs','them','then','there','these','they','this','those','to',
    'too','unless','until','us','use','used','using','was','way','we','well','went',
    'were','weren','what','when','where','which','while','who','whom','whose','why',
    'will','with','would','would','wouldn','yet','you','your','yours'
);

// change the new question form when the format selector changes

function change_format (obj) {
//    alert(obj.id);
    var format = obj.value;
//    alert("changing format to " + format);
    var size = $('#size');
    var maxlen = $('#maxlen');
    var datatype = $('#datatype');
    var options = $('#options');
    var required = $('#required');
    var placeholder = $('#placeholder');
    var preset = $('#preset');
    var checked = $('#checked');
    var min = $('#min');
    var max = $('#max');
    var step = $('#step');
    if (allow_size[format]) {
	size.removeAttr("disabled");
	size.parent().show();
    }
    else {
	size.attr("disabled","disabled");
	size.parent().hide();
    }
    if (allow_maxlen[format]) {
	maxlen.removeAttr("disabled");
	maxlen.parent().show();
    }
    else {
	maxlen.attr("disabled","disabled");
	maxlen.parent().hide();
    }
    if (allow_datatype[format]) {
	datatype.removeAttr("disabled");
	datatype.parent().show();
    }
    else {
	datatype.attr("disabled","disabled");
	datatype.parent().hide();
    }
    if (allow_options[format]) {
	options.removeAttr("disabled");
	options.parent().show();
    }
    else {
	options.attr("disabled","disabled");
	options.parent().hide();
    }
    if (allow_placeholder[format]) {
	placeholder.removeAttr("disabled");
	placeholder.parent().show();
    }
    else {
	placeholder.attr("disabled","disabled");
	placeholder.parent().hide();
    }
    if (allow_preset[format]) {
	preset.removeAttr("disabled");
	preset.parent().show();
    }
    else {
	preset.attr("disabled","disabled");
	preset.parent().hide();
    }
    if (allow_required[format]) {
	required.removeAttr("disabled");
	required.parent().show();
    }
    else {
	required.attr("disabled","disabled");
	required.parent().hide();
    }
    if (allow_checked[format]) {
	checked.removeAttr("disabled");
	checked.parent().show();
    }
    else {
	checked.attr("disabled","disabled");
	checked.parent().hide();
    }
    // numeric options
    if (allow_min[format]) {
	min.removeAttr("disabled");
	max.removeAttr("disabled");
	step.removeAttr("disabled");
	min.parent().show();
    }
    else {
	min.attr("disabled","disabled");
	max.attr("disabled","disabled");
	step.attr("disabled","disabled");
	min.parent().hide();
    }
    // switch help text
    var help_id = "#help_" + format;
    help_id = help_id.replace(" ","_");
    help_id = help_id.replace("+","_");
    //alert(help_id);
    // hide all help
    $(".format_help").children().hide();
    $(help_id).show();
}

function set_input_name (obj) {
    var prompt = obj.value;
    var name = $("#name");
//    alert(prompt);
    var len = $("#name").val().length;
//    alert(len);
    if (len == 0) {
	prompt = prompt.toLowerCase();
	prompt = prompt.replace(/[^\w]/g," ");    // punctuation
	prompt = prompt.replace(/ +$/g,"");       // trailing whitespace
	prompt = prompt.replace(/^(\d+)? +/g,""); // leading #s and whitespace
//	alert("new prompt: " + prompt);
	// reduce string length by dropping uninteresting words
	var words = prompt.split(" ");
	var n_word = words.length;
	var n_null = nullwords.length;
	var newwords = new Array();
	for (var i = 0; i < n_word; i++) {
	    var use = 1;
	    for (var j = 0; j < n_null; j++) {
		if (words[i] == nullwords[j]) {
		    use = 0;
		    break;
		}
	    }
	    if (use) newwords.push(words[i]);
	}
	prompt = newwords.join("_");
	//prompt = prompt.replace(/ /g,"_");
	name.attr("value",prompt);
    }
}

// submit the request to make a new question

//var modpath = "/cgi/mobu2/ex.cgi/admin";
function copy_question (obj) {
    var domid = $(obj).attr("id"); // qf_QQQ_FFF
    var copyid = domid.split("_");
    var qid = copyid[1];
    var fid = copyid[2];
//    var url = modpath + "_bare=2&copy=" + qid + "&id=" + fid;
    var url = modpath + "_bare=2&copy=" + qid + "&id=" + fid + "&confirm=1";
    $("#addq_"+qid).css("text-decoration","line-through");
    subRequestData("questionPopup"+qid,url);
}

// deprecated
function copy_question_confirm (obj) {
    var domid = $(obj).attr("id");
    var qfid = domid.split("_");
    var qid = qfid[0].split("copyq")[1];
    var fid = qfid[1].split("f")[1];
    var url = modpath + "_bare=2&copy=" + qid + "&id=" + fid + "&confirm=1";
    $("#q"+qid+"_f"+fid).css("text-decoration","line-through");
//    alert(url);
    subRequestData("questionPopup",url);
}

//====================== old ===========================

// submit the request to make a new question

function make_question (obj) {
    var fdata = get_form_data("new_question_form",1);
    var format = fdata['new_format'];
    format = format.replace(/\+/g," ");
    var post = "format=" + format + "&label=" + fdata['new_prompt'] + "&access=" + fdata['new_access'];
    if (allow_size[format]) {
	post = post.concat("&size=" + fdata['new_size']);
    }
    if (allow_validate[format]) {
	post = post.concat("&validate=" + fdata['new_validate']);
    }
    if (allow_value[format]) {
	post = post.concat("&value=" + fdata['new_value']);
    }
    else if (allow_answer[format]) {
	post = post.concat("&answer=" + fdata['new_answer']);
    }
    if (allow_required[format]) {
	post = post.concat("&required=" + fdata['new_required']);
    }
    if (allow_placeholder[format]) {
	post = post.concat("&placeholder=" + fdata['new_placeholder']);
    }
    if (allow_checked[format]) {
	post = post.concat("&checked=" + fdata['new_answer']);
    }
    var posturl = document.URL + "&_bare=2";
//    alert(post);
    sendAsyncPost(posturl,"new_question",post);
}

// perform the AJAX post for making new questions

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

