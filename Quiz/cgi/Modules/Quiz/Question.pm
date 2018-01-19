#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2017 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
#
#   ExSite is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   ExSite is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with ExSite; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Users requiring warranty coverage and/or support may arrange alternate
#   commercial licensing for ExSite, by contacting Exware Solutions 
#   via the website noted above.
#
#----------------------------------------------------------------------------

package Modules::Quiz::Question;

use strict;
use ExSite::Config;
use ExSite::Content;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;

use vars qw(@ISA);
@ISA = qw(Modules::Forms::Question);

sub is_markable {
    my $this = shift;
    return $this->format =~ /radio|select/;
}

sub correct_answer {
    my $this = shift;
    return $this->emeta("answer");
}

sub score {
    my $this = shift;
    return $this->emeta("score") || 1;
}

sub stack_options {
    my ($this,@opt) = @_;
    return 1;  # always stack quiz options
}

sub editmeta_template { 
    my ($this) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    return $ml->p("Full question, as displayed to the user${br}[[title:input]]").
	$ml->p("Brief form of question, used in reports${br}[[label:input]]").
	$ml->p("Question name used for HTML encoding${br}[[name:input]]").
#	$ml->p("Minimum access level to see this question${br}[[access:input]]").
	$ml->p("[[_meta_format:prompt]]${br}[[_meta_format:input]]").
	$ml->p("Options (select, multiselect, radio, and checklists only)${br}[[_meta_options:input]]").
	$ml->p("Correct answer${br}[[_meta_answer:input]]").
	$ml->p("Score${br}[[_meta_score:input]]");

#	$ml->tr($ml->td("For numeric inputs only (number, range):",{colspan=>3})).
#	$ml->tr($ml->td("[[_meta_min:prompt]]: [[_meta_min:input]]").$ml->td("[[_meta_max:prompt]]: [[_meta_max:input]]").$ml->td("[[_meta_step:prompt]]: [[_meta_step:input]]")).
}

sub editmeta_fields {
    my $this = shift;
    return ["title","label","name","status"];
}



1;
