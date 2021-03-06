
'use strict';

!function ($) {

    function MutableTimer(elem, options, cb) {
        var _this = this,
            duration = options.duration,
            //options is an object for easily adding features later.
            nameSpace = Object.keys(elem.data())[0] || 'timer',
            remain = -1,
            start,
            timer;

        this.isPaused = false;

        this.restart = function (newduration) {
            remain = -1;
            clearTimeout(timer);

            if(typeof newduration !== 'undefined') {
                duration = newduration
            }

            this.start();
        };

        this.start = function () {
            this.isPaused = false;
            // if(!elem.data('paused')){ return false; }//maybe implement this sanity check if used for other things.
            clearTimeout(timer);
            remain = remain <= 0 ? duration : remain;
            elem.data('paused', false);
            start = Date.now();
            timer = setTimeout(function () {
                if (options.infinite) {
                    _this.restart(); //rerun the timer.
                }
                if (cb && typeof cb === 'function') {
                    cb();
                }
            }, remain);
            elem.trigger('timerstart.zf.' + nameSpace);
        };

        this.pause = function () {
            this.isPaused = true;
            //if(elem.data('paused')){ return false; }//maybe implement this sanity check if used for other things.
            clearTimeout(timer);
            elem.data('paused', true);
            var end = Date.now();
            remain = remain - (end - start);
            elem.trigger('timerpaused.zf.' + nameSpace);
        };
    }


    Foundation.MutableTimer = MutableTimer;
}(jQuery);

'use strict';

!function($) {

    /**
     * Modified Orbit module.
     * @module foundation.timedorbit
     * @requires foundation.util.keyboard
     * @requires foundation.util.motion
     * @requires foundation.util.timerAndImageLoader
     * @requires foundation.util.touch
     */

    class TimedOrbit {
        /**
         * Creates a new instance of a timed orbit carousel.
         * @class
         * @param {jQuery} element - jQuery object to make into an Orbit Carousel.
         * @param {Object} options - Overrides to the default plugin settings.
         */
        constructor(element, options){
            this.$element = element;
            this.options = $.extend({}, TimedOrbit.defaults, this.$element.data(), options);

            this._init();

            Foundation.registerPlugin(this, 'TimedOrbit');
            Foundation.Keyboard.register('TimedOrbit', {
                'ltr': {
                    'ARROW_RIGHT': 'next',
                    'ARROW_LEFT': 'previous'
                },
                'rtl': {
                    'ARROW_LEFT': 'next',
                    'ARROW_RIGHT': 'previous'
                }
            });
        }

        /**
         * Initializes the plugin by creating jQuery collections, setting attributes, and starting the animation.
         * @function
         * @private
         */
        _init() {
            this._reset();

            this.$wrapper = this.$element.find(`.${this.options.containerClass}`);
            this.$slides = this.$element.find(`.${this.options.slideClass}`);

            var initActive = this.$slides.filter('.is-active'),
                id = this.$element[0].id || Foundation.GetYoDigits(6, 'timedorbit');

            this.$element.attr({
                'data-resize': id,
                'id': id
            });

            if (!initActive.length) {
                this.$slides.eq(0).addClass('is-active');
            }

            if (!this.options.useMUI) {
                this.$slides.addClass('no-motionui');
            }

            this._prepareForTimedOrbit();//hehe

            if (this.options.bullets) {
                this._loadBullets();
            }

            this._events();

            if (this.options.autoPlay && this.$slides.length > 1) {
                this.geoSync();
            }

            if (this.options.accessible) { // allow wrapper to be focusable to enable arrow navigation
                this.$wrapper.attr('tabindex', 0);
            }
        }

        /**
         * Creates a jQuery collection of bullets, if they are being used.
         * @function
         * @private
         */
        _loadBullets() {
            this.$bullets = this.$element.find(`.${this.options.boxOfBullets}`).find('button');
        }

        /**
         * Sets a `timer` object on the orbit, and starts the counter for the next slide.
         * @function
         */
        geoSync() {
            var _this = this;

            var $newSlide = this.$slides.first();
            var delay = _this._calculateDelay($newSlide);
            _this.$element.trigger('slidechange.zf.timedorbit', [$newSlide, delay]);

            this.timer = new Foundation.MutableTimer(
                this.$element,
                {
                    duration: delay,
                    infinite: false
                },
                function() {
                    _this.changeSlide(true);
                });
            this.timer.start();
        }

        /**
         * Sets wrapper and slide heights for the orbit.
         * @function
         * @private
         */
        _prepareForTimedOrbit() {
            var _this = this;
            if(this.options.setHeight) {
                this._setWrapperHeight();
            }
        }

        /**
         * Calulates the height of each slide in the collection, and uses the tallest one for the wrapper height.
         * @function
         * @private
         * @param {Function} cb - a callback function to fire when complete.
         */
        _setWrapperHeight(cb) {//rewrite this to `for` loop
            var max = 0, temp, counter = 0, _this = this;

            this.$slides.each(function() {
                temp = this.getBoundingClientRect().height;
                $(this).attr('data-slide', counter);

                if (_this.$slides.filter('.is-active')[0] !== _this.$slides.eq(counter)[0]) {//if not the active slide, set css position and display property
                    $(this).css({'position': 'relative', 'display': 'none'});
                }
                max = temp > max ? temp : max;
                counter++;
            });

            if (counter === this.$slides.length) {
                this.$wrapper.css({'height': max}); //only change the wrapper height property once.
                if(cb) {cb(max);} //fire callback with max height dimension.
            }
        }

        /**
         * Sets the max-height of each slide.
         * @function
         * @private
         */
        _setSlideHeight(height) {
            this.$slides.each(function() {
                $(this).css('max-height', height);
            });
        }

        /**
         * Adds event listeners to basically everything within the element.
         * @function
         * @private
         */
        _events() {
            var _this = this;

            //***************************************
            //**Now using custom event - thanks to:**
            //**      Yohai Ararat of Toronto      **
            //***************************************
            //
            this.$element.off('.resizeme.zf.trigger').on({
                'resizeme.zf.trigger': this._prepareForTimedOrbit.bind(this)
            })
            if (this.$slides.length > 1) {

                if (this.options.swipe) {
                    this.$slides.off('swipeleft.zf.timedorbit swiperight.zf.timedorbit')
                        .on('swipeleft.zf.timedorbit', function(e){
                            e.preventDefault();
                            _this.changeSlide(true);
                        }).on('swiperight.zf.timedorbit', function(e){
                            e.preventDefault();
                            _this.changeSlide(false);
                        });
                }
                //***************************************

                if (this.options.autoPlay) {
                    this.$slides.on('click.zf.timedorbit', function() {
                        _this.$element.data('clickedOn', _this.$element.data('clickedOn') ? false : true);
                        _this.timer[_this.$element.data('clickedOn') ? 'pause' : 'start']();
                    });

                    if (this.options.pauseOnHover) {
                        this.$element.on('mouseenter.zf.timedorbit', function() {
                            _this.timer.pause();
                        }).on('mouseleave.zf.timedorbit', function() {
                            if (!_this.$element.data('clickedOn')) {
                                _this.timer.start();
                            }
                        });
                    }
                }

                if (this.options.navButtons) {
                    var $controls = this.$element.find(`.${this.options.nextClass}, .${this.options.prevClass}`);
                    $controls.attr('tabindex', 0)
                    //also need to handle enter/return and spacebar key presses
                        .on('click.zf.timedorbit touchend.zf.timedorbit', function(e){
	                        e.preventDefault();
                            _this.timer.start();
                            _this.changeSlide($(this).hasClass(_this.options.nextClass));
                        });
                }

                if (this.options.bullets) {
                    this.$bullets.on('click.zf.timedorbit touchend.zf.timedorbit', function() {
                        if (/is-active/g.test(this.className)) { return false; }//if this is active, kick out of function.
                        var idx = $(this).data('slide'),
                            ltr = idx > _this.$slides.filter('.is-active').data('slide'),
                            $slide = _this.$slides.eq(idx);

                        _this.changeSlide(ltr, $slide, idx);
                    });
                }

                if (this.options.accessible) {
                    this.$wrapper.add(this.$bullets).on('keydown.zf.timedorbit', function(e) {
                        // handle keyboard event with keyboard util
                        Foundation.Keyboard.handleKey(e, 'TimedOrbit', {
                            next: function() {
                                _this.changeSlide(true);
                            },
                            previous: function() {
                                _this.changeSlide(false);
                            },
                            handled: function() { // if bullet is focused, make sure focus moves
                                if ($(e.target).is(_this.$bullets)) {
                                    _this.$bullets.filter('.is-active').focus();
                                }
                            }
                        });
                    });
                }
            }
        }

        /**
         * Resets TimedOrbit so it can be reinitialized
         */
        _reset() {
            // Don't do anything if there are no slides (first run)
            if (typeof this.$slides == 'undefined') {
                return;
            }

            if (this.$slides.length > 1) {
                // Remove old events
                this.$element.off('.zf.timedorbit').find('*').off('.zf.timedorbit')

                // Restart timer if autoPlay is enabled
                if (this.options.autoPlay) {
                    this.timer.restart();
                }

                // Reset all sliddes
                this.$slides.each(function(el) {
                    $(el).removeClass('is-active is-active is-in')
                        .removeAttr('aria-live')
                        .hide();
                });

                // Show the first slide
                this.$slides.first().addClass('is-active').show();

                // Triggers when the slide has finished animating
                this.$element.trigger('slidechange.zf.timedorbit', [this.$slides.first()]);

                // Select first bullet if bullets are present
                if (this.options.bullets) {
                    this._updateBullets(0);
                }
            }
        }

        /**
         * Changes the current slide to a new one.
         * @function
         * @param {Boolean} isLTR - flag if the slide should move left to right.
         * @param {jQuery} chosenSlide - the jQuery element of the slide to show next, if one is selected.
         * @param {Number} idx - the index of the new slide in its collection, if one chosen.
         * @fires TimedOrbit#slidechange
         */
        changeSlide(isLTR, chosenSlide, idx) {
            if (!this.$slides) {return; } // Don't freak out if we're in the middle of cleanup
            var $curSlide = this.$slides.filter('.is-active').eq(0);

            if (/mui/g.test($curSlide[0].className)) { return false; } //if the slide is currently animating, kick out of the function

            var $firstSlide = this.$slides.first(),
                $lastSlide = this.$slides.last(),
                dirIn = isLTR ? 'Right' : 'Left',
                dirOut = isLTR ? 'Left' : 'Right',
                _this = this,
                $newSlide;

            if (!chosenSlide) { //most of the time, this will be auto played or clicked from the navButtons.
                $newSlide = isLTR ? //if wrapping enabled, check to see if there is a `next` or `prev` sibling, if not, select the first or last slide to fill in. if wrapping not enabled, attempt to select `next` or `prev`, if there's nothing there, the function will kick out on next step. CRAZY NESTED TERNARIES!!!!!
                (this.options.infiniteWrap ? $curSlide.next(`.${this.options.slideClass}`).length ? $curSlide.next(`.${this.options.slideClass}`) : $firstSlide : $curSlide.next(`.${this.options.slideClass}`))//pick next slide if moving left to right
                :
                (this.options.infiniteWrap ? $curSlide.prev(`.${this.options.slideClass}`).length ? $curSlide.prev(`.${this.options.slideClass}`) : $lastSlide : $curSlide.prev(`.${this.options.slideClass}`));//pick prev slide if moving right to left
            } else {
                $newSlide = chosenSlide;
            }

            if ($newSlide.length) {
                /**
                 * Triggers before the next slide starts animating in and only if a next slide has been found.
                 * @event TimedOrbit#beforeslidechange
                 */
                this.$element.trigger('beforeslidechange.zf.timedorbit', [$curSlide, $newSlide]);

                if (this.options.bullets) {
                    idx = idx || this.$slides.index($newSlide); //grab index to update bullets
                    this._updateBullets(idx);
                }

                var delay = this.options.minDelay;

                if (this.options.useMUI && !this.$element.is(':hidden')) {
                    Foundation.Motion.animateIn(
                        $newSlide.addClass('is-active').css({'position': 'absolute', 'top': 0}),
                        this.options[`animInFrom${dirIn}`],
                        function(){
                            $newSlide.css({'position': 'relative', 'display': 'block'})
                                .attr('aria-live', 'polite');

                            delay = _this._calculateDelay($newSlide);

                            if(_this.options.autoPlay && !_this.timer.isPaused){
                                _this.timer.restart(delay);
                            }

                            /**
                             * Triggers when the slide has finished animating in.
                             * @event TimedOrbit#slidechange
                             */
                            _this.$element.trigger('slidechange.zf.timedorbit', [$newSlide, delay]);
                        });

                    Foundation.Motion.animateOut(
                        $curSlide.removeClass('is-active'),
                        this.options[`animOutTo${dirOut}`],
                        function(){
                            $curSlide.removeAttr('aria-live');
                            //do stuff?
                        });
                } else {
                    $curSlide.removeClass('is-active is-in').removeAttr('aria-live').hide();
                    $newSlide.addClass('is-active is-in').attr('aria-live', 'polite').show();
                    if (this.options.autoPlay && !this.timer.isPaused) {
                        delay = _this._calculateDelay($newSlide);
                        this.timer.restart(delay);
                    }
                }
            }
        }

        /**
         * Updates the active state of the bullets, if displayed.
         * @function
         * @private
         * @param {Number} idx - the index of the current slide.
         */
        _updateBullets(idx) {
            var $oldBullet = this.$element.find(`.${this.options.boxOfBullets}`)
                .find('.is-active').removeClass('is-active').blur(),
                span = $oldBullet.find('span:last').detach(),
                $newBullet = this.$bullets.eq(idx).addClass('is-active').append(span);
        }

        /**
         * Destroys the carousel and hides the element.
         * @function
         */
        destroy() {
            this.$element.off('.zf.timedorbit').find('*').off('.zf.timedorbit').end().hide();
            Foundation.unregisterPlugin(this);
        }

        _calculateDelay($slide) {
            var content = $slide.find('.slide');
            var height  = $(content).height();
            var slide   = $slide.height();

            if(height > slide) { height = slide; }
            return this.options.minDelay + ( (this.options.maxDelay - this.options.minDelay) *
                                             ( height / slide ));
        }
    }

    TimedOrbit.defaults = {
        /**
         * Tells the JS to look for and loadBullets.
         * @option
         * @type {boolean}
         * @default true
         */
        bullets: true,
        /**
         * Tells the JS to apply event listeners to nav buttons
         * @option
         * @type {boolean}
         * @default true
         */
        navButtons: true,
        /**
         * motion-ui animation class to apply
         * @option
         * @type {string}
         * @default 'slide-in-right'
         */
        animInFromRight: 'slide-in-right',
        /**
         * motion-ui animation class to apply
         * @option
         * @type {string}
         * @default 'slide-out-right'
         */
        animOutToRight: 'slide-out-right',
        /**
         * motion-ui animation class to apply
         * @option
         * @type {string}
         * @default 'slide-in-left'
         *
         */
        animInFromLeft: 'slide-in-left',
        /**
         * motion-ui animation class to apply
         * @option
         * @type {string}
         * @default 'slide-out-left'
         */
        animOutToLeft: 'slide-out-left',
        /**
         * Allows TimedOrbit to automatically animate on page load.
         * @option
         * @type {boolean}
         * @default true
         */
        autoPlay: true,
        /**
         * Minimum time delay, in ms, between slide transitions
         * @option
         * @type {number}
         * @default 5000
         */
        minDelay: 5000,
        /**
         * Maximum time delay, in ms, between slide transitions
         * @option
         * @type {number}
         * @default 5000
         */
        maxDelay: 15000,
        /**
         * Allows TimedOrbit to infinitely loop through the slides
         * @option
         * @type {boolean}
         * @default true
         */
        infiniteWrap: true,
        /**
         * Allows the TimedOrbit slides to bind to swipe events for mobile, requires an additional util library
         * @option
         * @type {boolean}
         * @default true
         */
        swipe: true,
        /**
         * Allows the timing function to pause animation on hover.
         * @option
         * @type {boolean}
         * @default false
         */
        pauseOnHover: false,
        /**
         * Allows TimedOrbit to bind keyboard events to the slider, to animate frames with arrow keys
         * @option
         * @type {boolean}
         * @default true
         */
        accessible: true,
        /**
         * Class applied to the container of TimedOrbit
         * @option
         * @type {string}
         * @default 'orbit-container'
         */
        containerClass: 'timedorbit-container',
        /**
         * Class applied to individual slides.
         * @option
         * @type {string}
         * @default 'orbit-slide'
         */
        slideClass: 'timedorbit-slide',
        /**
         * Class applied to the bullet container. You're welcome.
         * @option
         * @type {string}
         * @default 'timedorbit-bullets'
         */
        boxOfBullets: 'timedorbit-bullets',
        /**
         * Class applied to the `next` navigation button.
         * @option
         * @type {string}
         * @default 'timedorbit-next'
         */
        nextClass: 'timedorbit-next',
        /**
         * Class applied to the `previous` navigation button.
         * @option
         * @type {string}
         * @default 'orbit-previous'
         */
        prevClass: 'timedorbit-previous',
        /**
         * Boolean to flag the js to use motion ui classes or not. Default to true for backwards compatability.
         * @option
         * @type {boolean}
         * @default true
         */
        useMUI: true,

        setHeight: true
    };

    // Window exports
    Foundation.plugin(TimedOrbit, 'TimedOrbit');

}(jQuery);
