(function () {
    const firebaseConfig = {
        apiKey: "AIzaSyAL6rvtbGZoWOQxm2o3fYxvFniwKz9GpXM",
        authDomain: "raygain-cf637.firebaseapp.com",
        projectId: "raygain-cf637",
        storageBucket: "raygain-cf637.firebasestorage.app",
        messagingSenderId: "258723115236",
        appId: "1:258723115236:web:766902037a28c178e6fcf1",
        measurementId: "G-7DXLCJCLVE"
    };

    let db = null;
    if (window.firebase) {
        if (!firebase.apps.length) {
            firebase.initializeApp(firebaseConfig);
        }
        db = firebase.firestore();
        // Avoid Firestore WebChannel issues (often seen as /Write/channel errors) on some networks/browsers.
        try { db.settings({ experimentalForceLongPolling: true, useFetchStreams: false, merge: true }); } catch (e) {}
    }

    const EMAILJS_SERVICE_ID = 'service_8atajk9';
    const EMAILJS_TEMPLATE_ID = 'template_yp68fop';
    const RAYGAIN_EMAIL_SENDER = 'RayGainPT@gmail.com';
    const CLINIC_CONTACT_NUMBER = '09972375959';
    const CLINIC_LOCATION = 'Butol Santiago Ilocos Sur Zone 3';

    const calendarTitle = document.getElementById('calendarTitle');
    const calendarGrid = document.getElementById('calendarGrid');
    const prevMonthBtn = document.getElementById('prevMonthBtn');
    const nextMonthBtn = document.getElementById('nextMonthBtn');

    const serviceButtons = Array.from(document.querySelectorAll('[data-service]'));
    const timeButtons = Array.from(document.querySelectorAll('[data-slot]'));

    const selectedDayText = document.getElementById('selectedDayText');
    const summaryService = document.getElementById('summaryService');
    const summaryDate = document.getElementById('summaryDate');
    const summaryTime = document.getElementById('summaryTime');
    const confirmBookingBtn = document.getElementById('confirmBookingBtn');
    const bookingMessage = document.getElementById('bookingMessage');
    const bookingSuccessModal = document.getElementById('bookingSuccessModal');
    const bookingOkBtn = document.getElementById('bookingOkBtn');
    const cancelAppointmentBtn = document.getElementById('cancelAppointmentBtn');
    const cancelConfirmBox = document.getElementById('cancelConfirmBox');
    const confirmCancelOkBtn = document.getElementById('confirmCancelOkBtn');
    const confirmCancelBackBtn = document.getElementById('confirmCancelBackBtn');
    const inquiryDraftRaw = sessionStorage.getItem('raygainInquiryDraft');
    let inquiryDraft = null;
    try {
        inquiryDraft = inquiryDraftRaw ? JSON.parse(inquiryDraftRaw) : null;
    } catch (error) {
        inquiryDraft = null;
    }

    const AVAILABLE_WEEKDAYS = new Set([2, 4, 6]); // Tue, Thu, Sat
    const BLOCKED_RED_WEEKDAYS = new Set([0, 1, 3]); // Sun, Mon, Wed

    let viewMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    let selectedDate = null;
    let selectedService = '';
    let selectedSlot = '';
    let lastBookingDocId = '';

    function todayAtMidnight() {
        const now = new Date();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate());
    }

    function formatMonthTitle(date) {
        return date.toLocaleDateString(undefined, {
            year: 'numeric',
            month: 'long'
        });
    }

    function formatDate(date) {
        return date.toLocaleDateString(undefined, {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        });
    }

    function isSameDate(a, b) {
        return a && b &&
            a.getFullYear() === b.getFullYear() &&
            a.getMonth() === b.getMonth() &&
            a.getDate() === b.getDate();
    }

    function escapeHtml(value) {
        return String(value || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function buildBookingFullName(data) {
        return [
            data?.firstName || '',
            data?.middleName || '',
            data?.suffix || '',
            data?.lastName || ''
        ].map(function (value) { return String(value || '').trim(); }).filter(Boolean).join(' ') || 'Valued Patient';
    }

    function buildBookingEmailMessage(bookingId, bookingMeta) {
        const fullName = buildBookingFullName(inquiryDraft);
        const html = `
            <p>Dear ${escapeHtml(fullName)},</p>
            <p>Warm Greetings! Your appointment request has been received at RayGain Physiotherapy Clinic.</p>
            <p><strong>Booking Details:</strong><br>
            * Service Type: ${escapeHtml(bookingMeta.serviceType)}<br>
            * Date: ${escapeHtml(bookingMeta.dateLabel)}<br>
            * Time: ${escapeHtml(bookingMeta.timeLabel)}<br>
            * Booking ID: ${escapeHtml(bookingId || 'N/A')}</p>
            <p><strong>Location:</strong><br>
            ${escapeHtml(CLINIC_LOCATION)}</p>
            <p>We will review your request and send a confirmation once it has been approved.</p>
            <p><strong>Contact:</strong><br>
            ${escapeHtml(CLINIC_CONTACT_NUMBER)}<br>
            ${escapeHtml(RAYGAIN_EMAIL_SENDER)}</p>
        `;

        const text = [
            `Dear ${fullName},`,
            '',
            'Warm Greetings! Your appointment request has been received at RayGain Physiotherapy Clinic.',
            '',
            'Booking Details:',
            `* Service Type: ${bookingMeta.serviceType}`,
            `* Date: ${bookingMeta.dateLabel}`,
            `* Time: ${bookingMeta.timeLabel}`,
            `* Booking ID: ${bookingId || 'N/A'}`,
            '',
            'Location:',
            CLINIC_LOCATION,
            '',
            'We will review your request and send a confirmation once it has been approved.',
            '',
            'Contact:',
            CLINIC_CONTACT_NUMBER,
            RAYGAIN_EMAIL_SENDER
        ].join('\n');

        return { fullName, html, text };
    }

    // Email is intentionally NOT sent here.
    // Emails are sent only when the therapist confirms the booking in the dashboard.

    function renderCalendar() {
        if (!calendarGrid || !calendarTitle) return;

        calendarTitle.textContent = formatMonthTitle(viewMonth);
        calendarGrid.innerHTML = '';

        const today = todayAtMidnight();

        const year = viewMonth.getFullYear();
        const month = viewMonth.getMonth();
        const firstDay = new Date(year, month, 1);
        const startWeekday = firstDay.getDay();
        const daysInMonth = new Date(year, month + 1, 0).getDate();

        for (let i = 0; i < startWeekday; i += 1) {
            const spacer = document.createElement('button');
            spacer.type = 'button';
            spacer.className = 'calendar-cell empty';
            spacer.disabled = true;
            spacer.textContent = '';
            calendarGrid.appendChild(spacer);
        }

        for (let day = 1; day <= daysInMonth; day += 1) {
            const cellDate = new Date(year, month, day);
            const weekday = cellDate.getDay();
            const cell = document.createElement('button');
            cell.type = 'button';
            cell.className = 'calendar-cell';
            cell.textContent = String(day);

            const isPast = cellDate < today;
            const canBook = AVAILABLE_WEEKDAYS.has(weekday);
            const isRedBlocked = BLOCKED_RED_WEEKDAYS.has(weekday);

            if (!isPast && canBook) {
                cell.classList.add('available');
                cell.addEventListener('click', function () {
                    selectedDate = cellDate;
                    bookingMessage.textContent = '';
                    renderCalendar();
                    renderSummary();
                });
            } else {
                cell.disabled = true;
                if (isPast || isRedBlocked) {
                    cell.classList.add('blocked-red');
                } else {
                    cell.classList.add('blocked');
                }
            }

            if (isSameDate(selectedDate, cellDate)) {
                cell.classList.add('selected');
            }

            calendarGrid.appendChild(cell);
        }

        if (prevMonthBtn) {
            const currentMonth = new Date(today.getFullYear(), today.getMonth(), 1);
            const isAtOrBeforeCurrent = viewMonth <= currentMonth;
            prevMonthBtn.disabled = isAtOrBeforeCurrent;
            prevMonthBtn.style.opacity = isAtOrBeforeCurrent ? '0.45' : '1';
            prevMonthBtn.style.cursor = isAtOrBeforeCurrent ? 'not-allowed' : 'pointer';
        }

        if (selectedDate && selectedDate < today) {
            selectedDate = null;
            renderSummary();
        }
    }

    function selectChoice(buttons, value, attrName) {
        buttons.forEach(function (btn) {
            const isSelected = btn.getAttribute(attrName) === value;
            btn.classList.toggle('is-selected', isSelected);
        });
    }

    function renderSummary() {
        selectedDayText.textContent = selectedDate ? formatDate(selectedDate) : 'No date selected yet';
        summaryService.textContent = selectedService || 'Not selected';
        summaryDate.textContent = selectedDate ? formatDate(selectedDate) : 'Not selected';
        summaryTime.textContent = selectedSlot || 'Not selected';
    }

    function toDateKey(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return year + '-' + month + '-' + day;
    }

    function openSuccessModal() {
        if (!bookingSuccessModal) return;
        bookingSuccessModal.classList.add('is-open');
        bookingSuccessModal.setAttribute('aria-hidden', 'false');
        if (cancelConfirmBox) cancelConfirmBox.hidden = true;
    }

    function closeSuccessModal() {
        if (!bookingSuccessModal) return;
        bookingSuccessModal.classList.remove('is-open');
        bookingSuccessModal.setAttribute('aria-hidden', 'true');
        if (cancelConfirmBox) cancelConfirmBox.hidden = true;
    }

    if (bookingOkBtn) {
        bookingOkBtn.addEventListener('click', function () {
            closeSuccessModal();
            // Redirect to home page after closing modal
            window.location.href = 'index.html';
        });
    }

    if (cancelAppointmentBtn) {
        cancelAppointmentBtn.addEventListener('click', function () {
            if (cancelConfirmBox) {
                cancelConfirmBox.hidden = false;
            }
        });
    }

    if (confirmCancelBackBtn) {
        confirmCancelBackBtn.addEventListener('click', function () {
            if (cancelConfirmBox) {
                cancelConfirmBox.hidden = true;
            }
        });
    }

    if (confirmCancelOkBtn) {
        confirmCancelOkBtn.addEventListener('click', async function () {
            if (!db || !lastBookingDocId) {
                bookingMessage.textContent = 'No appointment found to cancel.';
                bookingMessage.style.color = '#c24444';
                closeSuccessModal();
                return;
            }

            confirmCancelOkBtn.disabled = true;
            confirmCancelOkBtn.textContent = 'Cancelling...';

            try {
                await db.collection('appointments').doc(lastBookingDocId).delete();
                bookingMessage.textContent = 'Appointment cancelled successfully.';
                bookingMessage.style.color = '#c24444';
                lastBookingDocId = '';
                closeSuccessModal();
            } catch (error) {
                bookingMessage.textContent = 'Failed to cancel appointment. Please try again.';
                bookingMessage.style.color = '#c24444';
            } finally {
                confirmCancelOkBtn.disabled = false;
                confirmCancelOkBtn.textContent = 'OK';
            }
        });
    }

    serviceButtons.forEach(function (btn) {
        btn.addEventListener('click', function () {
            selectedService = btn.getAttribute('data-service') || '';
            selectChoice(serviceButtons, selectedService, 'data-service');
            renderSummary();
        });
    });

    timeButtons.forEach(function (btn) {
        btn.addEventListener('click', function () {
            selectedSlot = btn.getAttribute('data-slot') || '';
            selectChoice(timeButtons, selectedSlot, 'data-slot');
            renderSummary();
        });
    });

    if (prevMonthBtn) {
        prevMonthBtn.addEventListener('click', function () {
            const current = todayAtMidnight();
            const currentMonth = new Date(current.getFullYear(), current.getMonth(), 1);
            const candidate = new Date(viewMonth.getFullYear(), viewMonth.getMonth() - 1, 1);
            if (candidate < currentMonth) return;
            viewMonth = candidate;
            renderCalendar();
        });
    }

    if (nextMonthBtn) {
        nextMonthBtn.addEventListener('click', function () {
            viewMonth = new Date(viewMonth.getFullYear(), viewMonth.getMonth() + 1, 1);
            renderCalendar();
        });
    }

    if (confirmBookingBtn) {
        confirmBookingBtn.addEventListener('click', async function () {
            if (!selectedService || !selectedDate || !selectedSlot) {
                bookingMessage.textContent = 'Select service type, available date, and time slot first.';
                bookingMessage.style.color = '#c24444';
                return;
            }

            if (!db) {
                bookingMessage.textContent = 'Firebase is not available. Please refresh and try again.';
                bookingMessage.style.color = '#c24444';
                return;
            }

            confirmBookingBtn.disabled = true;
            confirmBookingBtn.textContent = 'Saving...';

            const bookingPayload = {
                serviceType: selectedService,
                date: toDateKey(selectedDate),
                dateLabel: formatDate(selectedDate),
                time: selectedSlot,
                source: 'booking-page',
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                inquiryData: inquiryDraft || null
            };

            try {
                const docRef = await db.collection('appointments').add(bookingPayload);
                lastBookingDocId = docRef.id;

                // Also save inquiry data to 'inquiries' collection for therapist-dashboard
                if (inquiryDraft) {
                    const inquiryRecord = {
                        ...inquiryDraft,
                        appointmentDate: toDateKey(selectedDate),
                        appointmentDateLabel: formatDate(selectedDate),
                        appointmentTime: selectedSlot,
                        appointmentSessionType: selectedService,
                        status: 'pending',
                        isDeleted: false,
                        bookingId: docRef.id,
                        bookingCreatedAt: firebase.firestore.FieldValue.serverTimestamp(),
                        inquiryCreatedAt: inquiryDraft.inquirySubmittedAt || new Date().toISOString()
                    };
                    await db.collection('inquiries').add(inquiryRecord);
                }

                bookingMessage.textContent = 'Booking saved successfully. Please wait for therapist confirmation.';
                bookingMessage.style.color = '#1d7b85';
                sessionStorage.removeItem('raygainInquiryDraft');
                openSuccessModal();
            } catch (error) {
                bookingMessage.textContent = 'Failed to save booking. Please try again.';
                bookingMessage.style.color = '#c24444';
            } finally {
                confirmBookingBtn.disabled = false;
                confirmBookingBtn.textContent = 'Confirm Booking';
            }
        });
    }

    renderCalendar();
    renderSummary();
})();
