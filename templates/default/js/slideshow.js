$(function() {
    $(".stopwatch").TimeCircles({ time: { Days: { show: false },
                                          Hours: { show: false },
                                          Minutes: { show: false },
                                          Seconds: { show: true }
                                        },
                                  count_past_zero: false,
                                  total_duration: duration
                                });

    $('#slideshow').on('slidechange.zf.orbit', function(event, newslide) {
        $(".stopwatch").TimeCircles().restart();

        // if moving from last to first, reload the page
        if( newslide.data('slide') == 0) {
            location.reload();
        }
    });
});