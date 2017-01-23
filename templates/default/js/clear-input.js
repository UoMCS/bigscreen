/* Based on suggestions from Kroehre and Johannes in the following
 * stackoverflow: http://stackoverflow.com/questions/5917776/clear-search-box-on-the-click-of-a-little-x-inside-of-it
 */
(function ($, undefined) {
    $.fn.clearable = function () {
        var $this = this;
        $this.wrap('<div class="clear-holder" />');
        var helper = $('<span class="clear-helper"><i class="fa fa-remove"></i></span>');
        $this.parent().append(helper);
        $this.parent().on('keyup', function() {
            if($this.val()) {
                helper.css('display', 'inline-block');
            } else helper.hide();
        });
        helper.click(function(){
            $this.val("");
            $this.trigger("keyup");
            helper.hide();
        });
    };
})(jQuery);
