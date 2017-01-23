(function ($, undefined) {
    $.fn.delaysearch = function (list) {
        var $this = this;

        var searchTimer;
        var delayLimit = 3;
        var delayTime  = 1500;

        $this.bind('keyup', function(e) {
            var target = e.target || e.srcElement; // IE have srcElement
            clearTimeout(searchTimer);

            var value = $this.val();
            if(value.length == 0 || value.length >= delayLimit) {
                list.search(value);
            } else {
                searchTimer = setTimeout(list.search, delayTime, value);
            }
        });

        return $this;
    };
})(jQuery);
