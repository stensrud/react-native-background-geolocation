package com.marianhello.bgloc.data;

import com.marianhello.bgloc.data.BackgroundLocation;
import java.util.ArrayList;
import android.os.Parcelable;
import android.os.Parcelable.Creator;
import android.os.Parcel;

public class BackgroundLocations implements Parcelable {
    public ArrayList<BackgroundLocation> locations;

    public BackgroundLocations () {
        this.locations = new ArrayList<BackgroundLocation>();
    }

    public BackgroundLocations (ArrayList<BackgroundLocation> locations) {
        this.locations = locations;
    }

    public BackgroundLocations (Parcel parcel) {
        this.locations = parcel.readArrayList(null);
    }

    @Override
    public int describeContents() {
        return 0;
    }

    @Override
    public void writeToParcel(Parcel dest, int flags) {
        dest.writeList(locations);
    }

    public static Creator<BackgroundLocations> CREATOR = new Creator<BackgroundLocations>() {

        @Override
        public BackgroundLocations createFromParcel(Parcel source) {
            return new BackgroundLocations(source);
        }

        @Override
        public BackgroundLocations[] newArray(int size) {
            return new BackgroundLocations[size];
        }
    };
}