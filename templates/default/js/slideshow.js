function _calculateCoverage($slide) {
    var content = $slide.find('.slide-content');
    var height  = $(content).height();
    var slide   = $slide.height();

    if(height > slide) { height = slide; }

    return (height * 100 / slide);
}


$(function() {
    $(".stopwatch").TimeCircles({ time: { Days: { show: false },
                                          Hours: { show: false },
                                          Minutes: { show: false },
                                          Seconds: { show: true }
                                        },
                                  count_past_zero: false,
                                  total_duration: (delays.maxDelay / 1000)
                                });

    $('.timedorbit-slide').each(function (index, elem) {
        var $elem = $(elem);

        var img = $elem.find('img.autofloat');
        if(img) {
            var coverage = _calculateCoverage($elem);
            if(coverage > 75) {
                img.addClass('float-right');
            } else {
                img.removeClass('float-right');
                img.addClass('float-left');
            }
        }
    });


    $('#slideshow').on('slidechange.zf.timedorbit', function(event, newslide, delay) {
        $('#timer').data('timer', delay / 1000);
        $('#timer').TimeCircles().restart();

        // if moving from last to first, and we've done enough loops, reload the page
        if((newslide.data('slide') == 0) && (--loops < 0)) {
            location.reload();
        }
    });

    new Foundation.TimedOrbit($('#slideshow'), delays);
});