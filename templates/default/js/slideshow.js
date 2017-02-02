$(function() {
    $(".stopwatch").TimeCircles({ time: { Days: { show: false },
                                          Hours: { show: false },
                                          Minutes: { show: false },
                                          Seconds: { show: true }
                                        },
                                  count_past_zero: false,
                                  total_duration: (delays.maxDelay / 1000)
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